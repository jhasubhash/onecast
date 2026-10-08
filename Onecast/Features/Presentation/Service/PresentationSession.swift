import AppKit
@preconcurrency import ApplicationServices

/// One presentation's effects on other apps' windows, recorded so each can be undone exactly.
@MainActor
final class PresentationSession {
    private struct MovedWindow {
        let window: AXUIElement
        /// AX space, read before the first write.
        let frame: CGRect
    }

    /// The display everything is presented on, chosen when the presentation starts.
    let display: CGDirectDisplayID
    private var moved: [MovedWindow] = []
    private var fullScreened: [AXUIElement] = []
    private var minimized: [AXUIElement] = []
    private var hidden: [NSRunningApplication] = []

    /// Full screen animates out; a frame written mid-animation lands on the wrong Space.
    private static let fullScreenExit: Duration = .milliseconds(900)

    init(display: CGDirectDisplayID) {
        self.display = display
    }

    /// The display holding most of `app`'s target window, nil when it has none.
    static func display(of app: NSRunningApplication) -> CGDirectDisplayID? {
        let application = AXWindowAccess.application(for: app.processIdentifier)
        guard let window = AXWindowAccess.targetWindow(in: application),
            let frame = AXWindowAccess.frame(of: window)
        else { return nil }
        let geometry = AXGeometry(screens: NSScreen.screens)
        return screen(containing: geometry.flip(frame)).flatMap(PresentationDisplayAccess.displayID)
    }

    // MARK: - Presenting

    /// Sizes `app`'s target window on the presentation display; false when it has no window yet.
    func present(
        _ app: NSRunningApplication, size: PresentationWindowSize, marginPercent: Int
    ) -> Bool {
        let application = AXWindowAccess.application(for: app.processIdentifier)
        guard let window = AXWindowAccess.targetWindow(in: application) else { return false }
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        guard size != .unchanged, !AXWindowAccess.isFullScreen(window) else { return true }

        let frameSize: PresentationWindowSize = size == .fullScreen ? .fill : size
        place(window, in: application, size: frameSize, marginPercent: marginPercent)
        if size == .fullScreen, enterFullScreen(window) {
            fullScreened.append(window)
        }
        return true
    }

    private func place(
        _ window: AXUIElement, in application: AXUIElement, size: PresentationWindowSize,
        marginPercent: Int
    ) {
        let geometry = AXGeometry(screens: NSScreen.screens)
        guard let current = AXWindowAccess.frame(of: window),
            let screen = PresentationDisplayAccess.screen(for: display)
                ?? Self.screen(containing: geometry.flip(current)),
            AXWindowAccess.isSettable(kAXPositionAttribute, on: window)
        else { return }
        let usable = geometry.flip(AXScreens.usableFrame(of: screen))
        guard
            let target = PresentationFrameEngine.frame(
                for: size, marginPercent: marginPercent, in: usable)
        else { return }

        if !moved.contains(where: { CFEqual($0.window, window) }) {
            moved.append(MovedWindow(window: window, frame: current))
        }
        let canResize = AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
        let restoreEnhancedUI =
            canResize ? AXWindowAccess.suppressEnhancedUserInterface(on: application) : {}
        defer { restoreEnhancedUI() }
        _ = AXWindowAccess.write(
            target, anchor: .centered, to: window, current: current, canResize: canResize,
            canvas: usable)
    }

    private func enterFullScreen(_ window: AXUIElement) -> Bool {
        guard AXWindowAccess.isSettable(AXWindowAccess.fullScreenAttribute as String, on: window)
        else { return false }
        return AXUIElementSetAttributeValue(
            window, AXWindowAccess.fullScreenAttribute, kCFBooleanTrue) == .success
    }

    // MARK: - Putting apps away

    /// `reach` limits a minimize to those window frames; `alsoHide` covers Spaces AX can't reach.
    func putAway(
        _ app: NSRunningApplication, as style: PresentationOtherApps, reach: [CGRect]? = nil,
        alsoHide: Bool = false
    ) {
        guard !app.isTerminated else { return }
        switch style {
        case .leave:
            return
        case .hide:
            hide(app)
        case .minimize:
            guard !app.isHidden else { return }
            let application = AXWindowAccess.application(for: app.processIdentifier)
            for window in AXWindowAccess.windows(in: application)
            where AXWindowAccess.isEligible(window) {
                if let reach {
                    guard let frame = AXWindowAccess.frame(of: window),
                        PresentationScopePolicy.matches(frame, anyOf: reach)
                    else { continue }
                }
                AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                minimized.append(window)
            }
            if alsoHide { hide(app) }
        }
    }

    private func hide(_ app: NSRunningApplication) {
        guard !app.isHidden else { return }
        // `hide()` answers false on macOS 26 even when it hid the app, so the request is kept.
        _ = app.hide()
        hidden.append(app)
    }

    /// Only an app this presentation hid, so one the user never had put away stays as it is.
    func hideAgain(_ app: NSRunningApplication) {
        guard !app.isTerminated, hidden.contains(where: { $0 == app }) else { return }
        _ = app.hide()
    }

    /// Every other app's ordinary windows, in AX space: on any Space, or only those shown now.
    static func windows(onScreenOnly: Bool = false) -> [PresentationWindow] {
        let options: CGWindowListOption =
            onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != own,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            let isOnScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
            return PresentationWindow(pid: pid, frame: frame, isOnScreen: isOnScreen)
        }
    }

    /// The presentation display's frame in AX space, for a scope that reaches only it.
    var displayFrame: CGRect {
        guard let screen = PresentationDisplayAccess.screen(for: display) else { return .null }
        return AXGeometry(screens: NSScreen.screens).flip(screen.frame)
    }

    // MARK: - Restoring

    /// First, so the frames written afterwards land on the desktop rather than in a closing Space.
    func leaveFullScreen() async {
        let windows = fullScreened.filter(AXWindowAccess.isFullScreen)
        fullScreened = []
        guard !windows.isEmpty else { return }
        for window in windows {
            AXUIElementSetAttributeValue(
                window, AXWindowAccess.fullScreenAttribute, kCFBooleanFalse)
        }
        try? await Task.sleep(for: Self.fullScreenExit)
    }

    /// Puts frames back (when asked), then the hidden apps, then their minimized windows.
    func restore(frames: Bool) {
        if frames {
            for record in moved where AXWindowAccess.isEligible(record.window) {
                guard let current = AXWindowAccess.frame(of: record.window) else { continue }
                _ = AXWindowAccess.write(
                    record.frame, anchor: .topLeading, to: record.window, current: current,
                    canResize: AXWindowAccess.isSettable(kAXSizeAttribute, on: record.window),
                    canvas: nil)
            }
        }
        for app in hidden where !app.isTerminated {
            _ = app.unhide()
        }
        for window in minimized {
            _ = AXWindowAccess.unminimize(window)
        }
        moved = []
        minimized = []
        hidden = []
    }

    /// The display holding most of `rect`, a Cocoa-space frame.
    private static func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            area(lhs.frame.intersection(rect)) < area(rhs.frame.intersection(rect))
        }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
