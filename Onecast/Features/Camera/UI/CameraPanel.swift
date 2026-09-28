import AppKit
import Carbon.HIToolbox

/// A camera surface's panel; keys go through `sendEvent`, so ↵ and Esc need no focused subview.
final class CameraPanel: NSPanel {
    enum Key {
        case primary
        case cancel
    }

    var onKey: ((Key) -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the palette, below a dialog: a confirmation must still land on top of it.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Suppresses AppKit's own window animation; `fadeIn`/`fadeOut` replace it.
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let onKey else {
            super.sendEvent(event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            onKey(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onKey(.primary)
        default:
            super.sendEvent(event)
        }
    }

    /// Optically centred on the screen under the cursor, the same lift a dialog takes.
    func centerOnCursorScreen() {
        guard let visible = NSScreen.underCursor?.visibleFrame else { return }
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * Self.centerLift))
    }

    private static let centerLift: CGFloat = 0.08

    /// The top-left corner's distance from the screen's own, so another resolution keeps the spot.
    func offset(on screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        return CGPoint(x: frame.minX - visible.minX, y: visible.maxY - frame.maxY)
    }

    /// Clamped whole onto the screen: a spot left on a larger display must never strand the panel.
    func place(at offset: CGPoint, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = frame.size
        let x = visible.minX + offset.x
        let y = visible.maxY - offset.y - size.height
        setFrameOrigin(
            NSPoint(
                x: min(max(x, visible.minX), visible.maxX - size.width),
                y: min(max(y, visible.minY), visible.maxY - size.height)))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
