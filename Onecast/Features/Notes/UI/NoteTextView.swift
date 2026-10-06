import AppKit

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?

    override var undoManager: UndoManager? { editorUndoManager }

    /// A Quick Action's result lands only while the note and its selection are as they were read.
    func replaceUnchangedSelection(with text: String, source: String, range: NSRange) -> Bool {
        guard isEditable, range.length > 0, string == source, selectedRange() == range,
            let textStorage, shouldChangeText(in: range, replacementString: text)
        else { return false }
        breakUndoCoalescing()
        textStorage.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        breakUndoCoalescing()
        return true
    }

    func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard window?.firstResponder === self,
            event.charactersIgnoringModifiers?.lowercased() == "z",
            modifiers == .command || modifiers == [.command, .shift]
        else { return super.performKeyEquivalent(with: event) }
        guard !event.isARepeat else { return true }
        breakUndoCoalescing()
        if modifiers == .command {
            editorUndoManager?.undo()
        } else {
            editorUndoManager?.redo()
        }
        return true
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
