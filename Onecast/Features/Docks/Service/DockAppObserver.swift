@preconcurrency import ApplicationServices
import Foundation

/// One app's `AXObserver`: window notifications arrive on the main run loop as plain events.
final class DockAppObserver: Sendable {
    enum Event: Sendable {
        case windowCreated(AXUIElement)
        case focusedWindowChanged
        case minimized(AXUIElement)
        case restored(AXUIElement)
        case destroyed(AXUIElement)
    }

    private final class Relay: Sendable {
        let handler: @Sendable (Event) -> Void

        init(_ handler: @escaping @Sendable (Event) -> Void) {
            self.handler = handler
        }
    }

    /// Windows announce these themselves; the app announces new and focused ones.
    private static let windowNotifications = [
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification
    ]

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let relay = Unmanaged<Relay>.fromOpaque(refcon).takeUnretainedValue()
        switch notification as String {
        case kAXWindowCreatedNotification: relay.handler(.windowCreated(element))
        case kAXFocusedWindowChangedNotification: relay.handler(.focusedWindowChanged)
        case kAXWindowMiniaturizedNotification: relay.handler(.minimized(element))
        case kAXWindowDeminiaturizedNotification: relay.handler(.restored(element))
        case kAXUIElementDestroyedNotification: relay.handler(.destroyed(element))
        default: break
        }
    }

    private let observer: AXObserver
    private let relay: Relay

    private init(observer: AXObserver, relay: Relay) {
        self.observer = observer
        self.relay = relay
    }

    /// Nil when the app refuses an observer, as a just-launched one does for a moment.
    static func attach(
        pid: pid_t, handler: @escaping @Sendable (Event) -> Void
    ) -> DockAppObserver? {
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created
        else { return nil }
        let relay = Relay(handler)
        let application = AXWindowAccess.application(for: pid, timeout: DockWindowAccess.sweepTimeout)
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            let status = AXObserverAddNotification(
                observer, application, name as CFString, Unmanaged.passUnretained(relay).toOpaque())
            guard status == .success || status == .notificationAlreadyRegistered else { return nil }
        }
        // Common modes, so a menu being tracked on main does not hold a minimize back.
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        return DockAppObserver(observer: observer, relay: relay)
    }

    /// Blocks on the app, so it runs off the main actor like every other AX call here.
    func watch(_ window: AXUIElement) {
        for name in Self.windowNotifications {
            AXObserverAddNotification(
                observer, window, name as CFString, Unmanaged.passUnretained(relay).toOpaque())
        }
    }

    func invalidate() {
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}
