import AppKit

/// Reads and sets a running app's Assign To, through the Dock's own menu wherever it can.
@MainActor
enum SpaceAssigner {
    private static let domain = "com.apple.spaces" as CFString
    private static let bindingsKey = "app-bindings" as CFString

    static func displayCount() -> Int {
        max(SkyLight()?.managedDisplays().count ?? 1, 1)
    }

    static func current(bundleID: String) -> SpaceAssignment {
        let displays = SkyLight()?.managedDisplays() ?? []
        return SpaceAssignment.resolve(
            binding: bindings()[bindingKey(bundleID)] as? String,
            displaySpaces: displays.map(\.spaceUUIDs))
    }

    /// The Dock keeps the bindings in memory, so only its menu changes them in place.
    static func assign(_ assignment: SpaceAssignment, bundleID: String, appURL: URL) {
        let choices = SpaceAssignment.choices(displayCount: displayCount())
        guard let choice = choices.firstIndex(of: assignment),
            let dock = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.dock"
            ).first
        else { return }
        let dockPID = dock.processIdentifier
        let appPath = appURL.standardizedFileURL.path
        Task {
            let pressed = await Task.detached {
                pressDockChoice(dockPID: dockPID, appPath: appPath, choice: choice, of: choices.count)
            }.value
            if !pressed { assignDirectly(assignment, bundleID: bundleID) }
        }
    }

    /// Without the Dock it applies now and persists for the Dock's next launch.
    private static func assignDirectly(_ assignment: SpaceAssignment, bundleID: String) {
        guard let skyLight = SkyLight() else { return }
        let displays = skyLight.managedDisplays()
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            switch assignment {
            case .allDesktops: skyLight.assignToAllSpaces(app.processIdentifier)
            case .display(let index):
                guard displays.indices.contains(index) else { continue }
                skyLight.assign(app.processIdentifier, toSpace: displays[index].currentSpaceID)
            case .none: skyLight.assign(app.processIdentifier, toSpace: 0)
            }
        }
        var updated = bindings()
        updated[bindingKey(bundleID)] = assignment.bindingValue(
            currentSpaces: displays.map(\.currentSpaceUUID))
        CFPreferencesSetAppValue(bindingsKey, updated as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
    }

    private static func bindings() -> [String: Any] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(bindingsKey, domain) as? [String: Any] ?? [:]
    }

    private static func bindingKey(_ bundleID: String) -> String { bundleID.lowercased() }

    /// Opens the app's Dock tile menu and presses one of Options' trailing Assign To rows.
    nonisolated private static func pressDockChoice(
        dockPID: pid_t, appPath: String, choice: Int, of choiceCount: Int
    ) -> Bool {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, 1)
        let tile = children(dock).flatMap(children).first { element in
            (value(element, kAXURLAttribute) as? URL)?.standardizedFileURL.path == appPath
        }
        guard let tile,
            AXUIElementPerformAction(tile, kAXShowMenuAction as CFString) == .success
        else { return false }
        guard let menu = awaitMenu(of: tile) else { return false }
        // Rows are matched by position: the Dock localizes every title, and Assign To closes Options.
        let options = children(menu).compactMap { children($0).first(where: isMenu) }.last
        let rows = options.map(children) ?? []
        guard rows.count >= choiceCount else {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            return false
        }
        let row = rows[rows.count - choiceCount + choice]
        return AXUIElementPerformAction(row, kAXPressAction as CFString) == .success
    }

    /// The Dock builds a tile's menu after the action returns, so it is polled for briefly.
    nonisolated private static func awaitMenu(of tile: AXUIElement) -> AXUIElement? {
        for _ in 0..<50 {
            if let menu = children(tile).first(where: isMenu) { return menu }
            usleep(10_000)
        }
        return nil
    }

    nonisolated private static func isMenu(_ element: AXUIElement) -> Bool {
        value(element, kAXRoleAttribute) as? String == kAXMenuRole
    }

    nonisolated private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    nonisolated private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value
    }
}
