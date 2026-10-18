import AppKit
import SwiftUI

/// Drags shelf items out as files, links or text, and reports presses and clicks for selection.
struct ShelfDragSource: NSViewRepresentable {
    /// Read when a drag starts, so it carries whatever is selected by then.
    let items: () -> [ShelfItem]
    var onPress: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onOpen: () -> Void = {}
    var menu: () -> NSMenu? = { nil }
    var onEnded: ([ShelfItem], NSDragOperation) -> Void = { _, _ in }

    func makeNSView(context: Context) -> ShelfDragSourceView { ShelfDragSourceView() }

    func updateNSView(_ view: ShelfDragSourceView, context: Context) {
        view.items = items
        view.onPress = onPress
        view.onClick = onClick
        view.onOpen = onOpen
        view.menuProvider = menu
        view.onEnded = onEnded
    }
}

final class ShelfDragSourceView: NSView, NSDraggingSource {
    var items: () -> [ShelfItem] = { [] }
    var onPress: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onOpen: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }
    var onEnded: ([ShelfItem], NSDragOperation) -> Void = { _, _ in }
    private var mouseDown: NSEvent?
    private var dragged: [ShelfItem] = []

    private static let dragThreshold: CGFloat = 3
    private static let iconSide: CGFloat = 32
    private static let stackOffset: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDown = event
        if event.clickCount == 2 {
            onOpen()
        } else {
            onPress(event.modifierFlags)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDown else { return }
        let start = down.locationInWindow
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) >= Self.dragThreshold else { return }
        mouseDown = nil
        dragged = items()
        guard !dragged.isEmpty else { return }
        let anchor = convert(start, from: nil)
        let dragging = dragged.enumerated().map { index, item in
            let draggingItem = NSDraggingItem(pasteboardWriter: Self.writer(for: item))
            let offset = CGFloat(min(index, 4)) * Self.stackOffset
            draggingItem.setDraggingFrame(
                NSRect(
                    x: anchor.x - Self.iconSide / 2 + offset, y: anchor.y - Self.iconSide / 2 - offset,
                    width: Self.iconSide, height: Self.iconSide),
                contents: ShelfIcon.image(for: item))
            return draggingItem
        }
        beginDraggingSession(with: dragging, event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard let down = mouseDown else { return }
        mouseDown = nil
        if down.clickCount == 1 { onClick(down.modifierFlags) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider() }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Move first, so Finder takes the file off the shelf; apps that only copy still accept it.
        context == .withinApplication ? .copy : [.move, .copy, .generic]
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        onEnded(dragged, operation)
    }

    private static func writer(for item: ShelfItem) -> any NSPasteboardWriting {
        switch item.content {
        case .file(let url), .link(let url): url as NSURL
        case .text(let text): text as NSString
        }
    }
}

/// A shelf item's glyph: the file's own icon, else a symbol for a link or text.
@MainActor
enum ShelfIcon {
    static func image(for item: ShelfItem) -> NSImage {
        switch item.content {
        case .file(let url): NSWorkspace.shared.icon(forFile: url.path)
        case .link: symbol("link")
        case .text: symbol("text.alignleft")
        }
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}

/// A menu row that runs a closure.
@MainActor
final class ShelfMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(_ title: String, symbol: String, action: @escaping @MainActor () -> Void) {
        run = action
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func runAction() {
        run()
    }
}
