import AppKit

/// A menu, folder or widget popover hung off a dock. It takes key without activating Onecast, so
/// Escape, the arrow keys and a widget's text fields work while the app in front keeps focus.
final class DockFloatingPanel: NSPanel {
    /// A key no control inside took; menus use it to drive their selection.
    var keyHandler: ((NSEvent) -> Void)?
    /// Escape, whether it reached the panel as a key or as a text field's cancel command.
    var onCancel: (() -> Void)?
    /// Sees every pointer event the panel receives, before it is dispatched.
    var pointerHandler: ((NSEvent) -> Void)?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode {
            onCancel?()
            return
        }
        keyHandler?(event)
    }

    private static let escapeKeyCode: UInt16 = 53

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        pointerHandler?(event)
        super.sendEvent(event)
    }
}
