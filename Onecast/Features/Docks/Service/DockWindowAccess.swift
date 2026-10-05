@preconcurrency import ApplicationServices
import AppKit

/// The dock's window reads and writes over AX. Nonisolated, so a hung app costs a worker.
enum DockWindowAccess {
    /// A sweep walks every app, so one hung process must not cost the full messaging timeout.
    static let sweepTimeout: Float = 0.2

    /// A standard window decoded for the main actor; `token` is its window-server ID.
    struct Window: Sendable {
        let token: String
        let title: String
        let isMinimized: Bool
        let element: AXUIElement
    }

    enum Restoration: Sendable {
        case restored, failed, gone
    }

    /// Every standard window the app reports, minimized ones included.
    static func windows(of pid: pid_t) -> [Window] {
        let application = AXWindowAccess.application(for: pid, timeout: sweepTimeout)
        return AXWindowAccess.windows(in: application).compactMap(window)
    }

    /// Nil for a sheet, a popover or a window the window server has not numbered yet.
    static func window(_ element: AXUIElement) -> Window? {
        AXUIElementSetMessagingTimeout(element, sweepTimeout)
        let isMinimized = AXWindowAccess.bool(element, kAXMinimizedAttribute) == true
        guard isStandard(element, minimized: isMinimized),
            let identifier = windowID(of: element)
        else { return nil }
        return Window(
            token: String(identifier), title: title(of: element), isMinimized: isMinimized,
            element: element)
    }

    /// macOS reports a minimized window's subrole as a dialog, and a real dialog cannot minimize.
    private static func isStandard(_ window: AXUIElement, minimized: Bool) -> Bool {
        let subrole = AXWindowAccess.string(window, kAXSubroleAttribute)
        return subrole == (kAXStandardWindowSubrole as String)
            || (minimized && subrole == (kAXDialogSubrole as String))
    }

    static func title(of window: AXUIElement) -> String {
        AXWindowAccess.string(window, kAXTitleAttribute) ?? ""
    }

    /// The token of the app's focused window, nil when it has none that is on screen.
    static func focusedWindowToken(of pid: pid_t) -> String? {
        let application = AXWindowAccess.application(for: pid, timeout: sweepTimeout)
        guard let focused = AXWindowAccess.element(application, kAXFocusedWindowAttribute),
            let window = window(focused), !window.isMinimized
        else { return nil }
        return window.token
    }

    /// Un-minimizes, raises and activates; macOS then follows the window to its Space.
    static func bringForward(_ window: AXUIElement, pid: pid_t) -> Restoration {
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        guard AXWindowAccess.unminimize(window) else {
            return AXWindowAccess.string(window, kAXRoleAttribute) == nil ? .gone : .failed
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            AXWindowAccess.focus(window, in: AXWindowAccess.application(for: pid), of: app)
        }
        return .restored
    }

    /// Main-actor and synchronous because a click needs its answer; short timeouts bound a hang.
    @MainActor
    static func minimizeFocusedWindow(of pid: pid_t) -> Bool {
        let application = AXWindowAccess.application(for: pid, timeout: sweepTimeout)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let window = AXWindowAccess.element(application, attribute) else { continue }
            AXUIElementSetMessagingTimeout(window, sweepTimeout)
            guard AXWindowAccess.isEligible(window), !AXWindowAccess.isFullScreen(window),
                AXWindowAccess.isSettable(kAXMinimizedAttribute, on: window)
            else { continue }
            return AXUIElementSetAttributeValue(
                window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        }
        return false
    }

    /// No public API names a window's server ID, and it is what keys a snapshot and a restore.
    private static func windowID(of window: AXUIElement) -> CGWindowID? {
        var identifier: CGWindowID = 0
        guard windowServerID(window, &identifier) == .success, identifier != 0 else { return nil }
        return identifier
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func windowServerID(
    _ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError
