import AppKit
import ColorSync

/// The one Cocoa↔AX converter. See docs/features/window-management.md#coordinate-space.
struct AXGeometry {
    let anchorHeight: CGFloat

    /// Snapshot once per command: `NSScreen.screens` can change, and mixing anchors corrupts.
    @MainActor
    init(screens: [NSScreen]) {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        anchorHeight = primary?.frame.height ?? 0
    }

    /// An involution through `maxY`, never scaled. docs/features/window-management.md
    func flip(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x, y: anchorHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Displays, converted into the AX space the geometry layer works in.
@MainActor
enum AXScreens {
    /// Cocoa screens flipped through one snapshotted anchor, never one each.
    static func converted(
        _ screens: [NSScreen], geometry: AXGeometry
    ) -> [WindowPlacementEngine.Screen] {
        let docks = AppCore.shared.dockCoordinator.panels.reservedFrames
        return screens.enumerated().map { index, screen in
            // A display with no number still needs a stable, collision-free id for this call.
            return WindowPlacementEngine.Screen(
                id: displayID(screen).map(Int.init) ?? -(index + 1),
                frame: geometry.flip(screen.frame),
                visibleFrame: geometry.flip(usableFrame(of: screen, docks: docks)))
        }
    }

    /// What window commands may use of a display: its visible frame less the custom docks on it.
    static func usableFrame(of screen: NSScreen) -> CGRect {
        usableFrame(of: screen, docks: AppCore.shared.dockCoordinator.panels.reservedFrames)
    }

    /// A dock with no display of its own follows the menu bar, as the dock itself does.
    private static func usableFrame(
        of screen: NSScreen, docks: [(displayKey: String?, edge: DockEdge, frame: CGRect)]
    ) -> CGRect {
        let key = screen.displayKey
        let menuBarKey = NSScreen.primary?.displayKey
        let reserved = docks.filter { ($0.displayKey ?? menuBarKey) == key }
            .map { DockInsets.Reservation(edge: insetEdge($0.edge), frame: $0.frame) }
        return DockInsets.usableFrame(visible: screen.visibleFrame, reserved: reserved)
    }

    private static func insetEdge(_ edge: DockEdge) -> DockInsets.Edge {
        switch edge {
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        }
    }

    /// Every connected display a layout can name, left to right, with its persistent identity.
    static func layoutScreens(geometry: AXGeometry) -> [WindowLayoutScreen] {
        let screens = NSScreen.screens
        let converted = converted(screens, geometry: geometry)
        let ordered = WindowPlacementEngine.ordered(converted)
        return ordered.compactMap { screen in
            guard let index = converted.firstIndex(where: { $0.id == screen.id }),
                let uuid = uuid(of: screens[index])
            else { return nil }
            return WindowLayoutScreen(
                display: WindowLayoutDisplay(uuid: uuid, name: screens[index].localizedName),
                screen: screen)
        }
    }

    /// Lowercased, so a stored identity and a live one can never miss each other on case.
    static func uuid(of screen: NSScreen) -> String? {
        guard let id = displayID(screen),
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return string.lowercased()
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }
}
