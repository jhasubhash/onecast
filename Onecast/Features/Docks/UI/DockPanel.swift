import AppKit

/// A dock's window: borderless and non-activating, so a click on it never takes focus from the
/// app in front, and never registered with `ActivationPolicy`, so no Dock icon appears for it.
final class DockPanel: NSPanel {
    init(layer: DockLayer) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        apply(layer: layer)
    }

    /// The system Dock's level for a floating dock, just above the desktop icons for a desktop one.
    func apply(layer: DockLayer) {
        switch layer {
        case .floating:
            level = .systemDock
            // Transient, so Mission Control hides it as it hides the real Dock.
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        case .desktop:
            level = .desktopWidget
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A tucked dock sits partly off screen, which AppKit would otherwise pull back.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
