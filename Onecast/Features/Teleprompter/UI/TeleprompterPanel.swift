import AppKit

/// The prompter's overlay: over every app, on every desktop, and left out of screen shares and recordings.
final class TeleprompterPanel: NSPanel {
    /// Lines the wheel moved, positive back towards the start.
    var onScroll: ((CGFloat) -> Void)?
    private let placement: TeleprompterPlacement

    private static let notchWidth: CGFloat = 480
    private static let floatingWidth: CGFloat = 520
    private static let visibleLines: CGFloat = 4
    private static let chrome: CGFloat = 56
    private static let floatingTopGap: CGFloat = 12

    /// The notch pill's text starts below the notch, or below the menu bar on a screen without one.
    static func topInset(for placement: TeleprompterPlacement, on screen: NSScreen?) -> CGFloat {
        guard placement == .notch, let screen else { return 0 }
        return screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
    }

    static func size(for placement: TeleprompterPlacement, textSize: Int, topInset: CGFloat) -> CGSize {
        let lineHeight = CGFloat(textSize) * 1.45
        return CGSize(
            width: placement == .notch ? notchWidth : floatingWidth,
            height: lineHeight * visibleLines + chrome + topInset)
    }

    init(content: NSView, placement: TeleprompterPlacement) {
        self.placement = placement
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        nameForAccessibility("teleprompter", title: "Teleprompter")
        isFloatingPanel = true
        // Over the menu bar, so the notch pill hangs from the very top of the screen.
        level = placement == .notch ? .statusBar : .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = placement == .floating
        // The audience sees the slides, never the script.
        sharingType = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = placement == .floating
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    /// Top centre of the screen: flush with its edge under a notch, just below the menu bar otherwise.
    func place(on screen: NSScreen?) {
        guard let screen else { return }
        let size = frame.size
        let top =
            placement == .notch ? screen.frame.maxY : screen.visibleFrame.maxY - Self.floatingTopGap
        setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: top - size.height))
    }

    /// Taken before any view sees it: the script scrolls by position, not by a scroll view.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, let onScroll else {
            super.sendEvent(event)
            return
        }
        let lines = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 24 : event.scrollingDeltaY
        if lines != 0 { onScroll(lines) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
