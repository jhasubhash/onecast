import AppKit

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?

    override var undoManager: UndoManager? { editorUndoManager }

    func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    /// Drawn in the text itself, so the find bar pushing the text down carries the placeholder too.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard textStorage?.length == 0 else { return }
        NSAttributedString(
            string: "Start writing…",
            attributes: [
                .font: font ?? NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor(Theme.Colors.textTertiary)
            ]
        ).draw(at: textContainerOrigin)
    }
}
