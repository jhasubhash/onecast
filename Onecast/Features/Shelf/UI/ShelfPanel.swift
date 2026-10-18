import AppKit
import Carbon.HIToolbox

/// The shelf's floating panel: on every desktop, above other apps, and never stealing activation.
final class ShelfPanel: NSPanel {
    enum Key {
        case escape
        case selectAll
        case delete
    }

    var onKey: ((Key) -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        nameForAccessibility("shelf", title: "Shelf")
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let onKey, let key = Self.key(for: event) else {
            super.sendEvent(event)
            return
        }
        onKey(key)
    }

    private static func key(for event: NSEvent) -> Key? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case kVK_Escape: return .escape
        case kVK_Delete, kVK_ForwardDelete: return .delete
        case kVK_ANSI_A where modifiers == .command: return .selectAll
        default: return nil
        }
    }

    /// Centred on the point, so a shake's drop lands straight on it, and kept whole on its screen.
    func center(on point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: min(max(point.x - size.width / 2, visible.minX), visible.maxX - size.width),
                y: min(max(point.y - size.height / 2, visible.minY), visible.maxY - size.height)))
    }

    /// Grows and shrinks from the top edge, so the header stays under the pointer.
    func setHeight(_ height: CGFloat) {
        guard frame.height != height else { return }
        var resized = frame
        resized.origin.y = frame.maxY - height
        resized.size.height = height
        setFrame(resized, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Takes drops for the whole shelf; the SwiftUI content inside registers for none of its own.
final class ShelfDropView: NSView {
    var onTargeted: ((Bool) -> Void)?
    /// The flag is a move: a file leaves where it was unless ⌥ is held or the source forbids it.
    var onDrop: ((NSPasteboard, Bool) -> Bool)?

    init(content: NSView) {
        super.init(frame: NSRect(origin: .zero, size: content.frame.size))
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        registerForDraggedTypes(ShelfIntake.draggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    /// A row dragged back onto its own shelf is already there.
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !(sender.draggingSource is ShelfDragSourceView) else { return [] }
        onTargeted?(true)
        return Self.moves(sender) ? .move : .copy
    }

    private static func moves(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingSourceOperationMask.contains(.move) && !NSEvent.modifierFlags.contains(.option)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargeted?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onTargeted?(false)
        return onDrop?(sender.draggingPasteboard, Self.moves(sender)) ?? false
    }
}
