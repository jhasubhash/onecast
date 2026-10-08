import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

@main
@MainActor
struct NotesEditorTests {
    private static var failures = 0

    static func main() async {
        _ = NSApplication.shared
        testLiteralEditingAndNativeCommands()
        testUndoAndRedoShortcuts()
        testUndoIsolation(afterUndo: false)
        testUndoIsolation(afterUndo: true)
        testQuickActionReplacement()
        testCharacterCountReports()
        testTextHeight()
        print(failures == 0 ? "Notes editor tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testTextHeight() {
        let input = NoteEditorInput(id: NoteID(rawValue: "Sizing.md"), source: "", epoch: 0)
        let editor = makeEditor(input: input)
        let emptyHeight = editor.textView.textHeight()
        check(
            "an empty note measures shorter than the visible area", emptyHeight < editor.textView.frame.height
        )

        let lines = String(repeating: "A line of text\n", count: 20)
        editor.textView.insertText(lines, replacementRange: editor.textView.selectedRange())
        let multilineHeight = editor.textView.textHeight()
        check("new lines grow the measured height at once", multilineHeight > emptyHeight)

        let wrappedText = String(repeating: "wrapped words ", count: 80)
        editor.textView.insertText(wrappedText, replacementRange: editor.textView.selectedRange())
        let wrappedHeight = editor.textView.textHeight()
        check("wrapped text grows the measured height without a newline", wrappedHeight > multilineHeight)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        paste("\n" + lines, into: editor.textView, from: pasteboard)
        check("paste grows the measured height", editor.textView.textHeight() > wrappedHeight)

        editor.textView.selectAll(nil)
        editor.textView.deleteBackward(nil)
        check(
            "deleting the text shrinks the measured height back", editor.textView.textHeight() == emptyHeight)
    }

    private static func testLiteralEditingAndNativeCommands() {
        let source = "# Heading\n\nThis is **bold** and [linked](https://example.com)."
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Literal.md"),
            source: source,
            epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: input, onSourceChange: { changes.append($0) })
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        check("the editor displays literal Markdown source", editor.textView.string == source)
        check("the plain editor enables native Find", editor.textView.usesFindBar)
        editor.textView.find(.showFindInterface)
        check("Find opens in the editor", editor.textView.enclosingScrollView?.isFindBarVisible == true)
        editor.textView.find(.hideFindInterface)
        check("Find closes in the editor", editor.textView.enclosingScrollView?.isFindBarVisible == false)
        check("Find closes without changing the source", editor.textView.string == source)

        let boldRange = (editor.textView.string as NSString).range(of: "**bold**")
        editor.textView.setSelectedRange(boldRange)
        copySelection(of: editor.textView, to: pasteboard)
        check(
            "native Copy preserves literal Markdown",
            pasteboard.string(forType: .string) == "**bold**")

        cutSelection(of: editor.textView, to: pasteboard)
        check("native Cut publishes one literal source update", changes.count == 1)
        check("native Cut removes the selected source", !editor.textView.string.contains("**bold**"))
        editor.coordinator.editorUndoManager.undo()
        check("native Undo restores the literal source", editor.textView.string == source)
        editor.coordinator.editorUndoManager.redo()
        check("native Redo restores the cut", editor.textView.string == changes.last)

        let end = (editor.textView.string as NSString).length
        editor.textView.setSelectedRange(NSRange(location: end, length: 0))
        paste(" [literal](url)", into: editor.textView, from: pasteboard)
        check("native Paste inserts exact source", editor.textView.string.hasSuffix(" [literal](url)"))

        let unicode = " 🧑🏽‍💻e\u{301}"
        editor.textView.insertText(unicode, replacementRange: editor.textView.selectedRange())
        check("emoji and combining marks remain exact", editor.textView.string.hasSuffix(unicode))

        let markedLocation = (editor.textView.string as NSString).length
        editor.textView.setSelectedRange(NSRange(location: markedLocation, length: 0))
        editor.textView.setMarkedText(
            "語",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.textView.unmarkText()
        check("marked text commits through native AppKit editing", editor.textView.string.hasSuffix("語"))
        check("every published value equals the displayed source", changes.last == editor.textView.string)
    }

    private static func testQuickActionReplacement() {
        let source = "The cat are here."
        let input = NoteEditorInput(id: NoteID(rawValue: "Action.md"), source: source, epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: input, onSourceChange: { changes.append($0) })
        let range = (source as NSString).range(of: "cat are")
        editor.textView.setSelectedRange(range)
        check("Quick Actions read the note selection", editor.textView.injectableSelection == "cat are")
        check(
            "Quick Actions replace an unchanged note selection",
            editor.textView.replaceUnchangedSelection(
                with: "cats are", source: source, range: range))
        check(
            "replacement updates the note through the editor",
            editor.textView.string == "The cats are here." && changes.last == editor.textView.string)
        editor.coordinator.editorUndoManager.undo()
        check("the replacement is undoable", editor.textView.string == source)

        editor.textView.setSelectedRange(NSRange(location: 0, length: 3))
        check(
            "a moved selection is not replaced",
            !editor.textView.replaceUnchangedSelection(with: "wrong", source: source, range: range))
        editor.textView.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.setSelectedRange(range)
        check(
            "a changed note is not replaced",
            !editor.textView.replaceUnchangedSelection(with: "wrong", source: source, range: range))
    }

    private static func testUndoAndRedoShortcuts() {
        let source = "# Heading\n🧑🏽‍💻e\u{301}"
        let input = NoteEditorInput(id: NoteID(rawValue: "Undo.md"), source: source, epoch: 1)
        var changes: [String] = []
        var counts: [Int] = []
        let editor = makeEditor(
            input: input,
            onSourceChange: { changes.append($0) }, onCountChange: { _, count in counts.append(count) })
        let undo = keyDown("z", keyCode: kVK_ANSI_Z, in: editor.window)
        let redo = keyDown("Z", keyCode: kVK_ANSI_Z, modifiers: [.command, .shift], in: editor.window)
        editor.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        editor.textView.insertText(" edit", replacementRange: editor.textView.selectedRange())
        check("⌘Z reaches the editor through its window", editor.window.performKeyEquivalent(with: undo))
        check("⌘Z restores exact source", editor.textView.string == source)
        check("Undo publishes the restored source for autosave", changes == [source + " edit", source])
        check("Undo updates the character count", counts.last == (source as NSString).length)
        check("⌘⇧Z reaches the editor through its window", editor.window.performKeyEquivalent(with: redo))
        check("⌘⇧Z restores the edit", editor.textView.string == source + " edit")
        check("Redo publishes the restored edit for autosave", changes.last == source + " edit")
        check("Redo updates the character count", counts.last == ((source + " edit") as NSString).length)

        editor.coordinator.editorUndoManager.undo()
        check("native Undo also publishes the source", changes.last == source)
        editor.coordinator.editorUndoManager.redo()
        check("native Redo also publishes the source", changes.last == source + " edit")
        _ = editor.window.performKeyEquivalent(with: undo)
        editor.textView.insertText(" new", replacementRange: editor.textView.selectedRange())
        check("an edit after Undo discards Redo", !editor.coordinator.editorUndoManager.canRedo)
        let updated = editor.textView.string
        let changeCount = changes.count
        let repeatedUndo = keyDown("z", keyCode: kVK_ANSI_Z, isARepeat: true, in: editor.window)
        check("a held Undo shortcut is consumed", editor.window.performKeyEquivalent(with: repeatedUndo))
        check("a held Undo shortcut does not repeat", editor.textView.string == updated)
        for modifiers: NSEvent.ModifierFlags in [[.command, .option], [.command, .control]] {
            let event = keyDown("z", keyCode: kVK_ANSI_Z, modifiers: modifiers, in: editor.window)
            check("other Z chords leave history alone", !editor.textView.performKeyEquivalent(with: event))
        }
        editor.window.makeFirstResponder(nil)
        check("an unfocused editor does not claim Undo", !editor.textView.performKeyEquivalent(with: undo))
        check("unrelated shortcuts change nothing", editor.textView.string == updated && changes.count == changeCount)
        editor.window.makeFirstResponder(editor.textView)
        check("empty Redo is handled locally", editor.window.performKeyEquivalent(with: redo))
        check("empty Redo changes nothing", editor.textView.string == updated && changes.count == changeCount)

        editor.coordinator.update(NoteEditorInput(id: input.id, source: updated, epoch: input.epoch))
        check("a source echo preserves Undo", editor.coordinator.editorUndoManager.canUndo)
        _ = editor.window.performKeyEquivalent(with: undo)
        check("Undo after a source echo still restores the note", editor.textView.string == source)
        check("Undo after a source echo still publishes the note", changes.last == source)
        let restoredChangeCount = changes.count
        check("empty Undo is handled locally", editor.window.performKeyEquivalent(with: undo))
        check("empty Undo publishes nothing", changes.count == restoredChangeCount)
    }

    private static func testUndoIsolation(afterUndo: Bool) {
        let first = NoteEditorInput(
            id: NoteID(rawValue: "First.md"),
            source: "First",
            epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: first, onSourceChange: { changes.append($0) })
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.textView.insertText(" edit", replacementRange: editor.textView.selectedRange())
        check("native editing registers Undo", editor.coordinator.editorUndoManager.canUndo)
        if afterUndo {
            editor.coordinator.editorUndoManager.undo()
            check("native Undo registers Redo", editor.coordinator.editorUndoManager.canRedo)
        }

        let second = NoteEditorInput(
            id: NoteID(rawValue: "Second.md"),
            source: "Second",
            epoch: 2)
        editor.coordinator.parent = view(for: second, onSourceChange: { changes.append($0) })
        editor.coordinator.update(second)
        check("switching notes installs the replacement source", editor.textView.string == "Second")
        check("switching notes clears stale Undo", !editor.coordinator.editorUndoManager.canUndo)
        check("switching notes clears stale Redo", !editor.coordinator.editorUndoManager.canRedo)
        editor.coordinator.editorUndoManager.undo()
        editor.coordinator.editorUndoManager.redo()
        check("Undo after a switch leaves the new note intact", editor.textView.string == "Second")

        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        editor.textView.insertText(" draft", replacementRange: editor.textView.selectedRange())
        let external = NoteEditorInput(id: second.id, source: "External", epoch: 3)
        editor.coordinator.parent = view(for: external, onSourceChange: { changes.append($0) })
        editor.coordinator.update(external)
        check("a clean external reload replaces the displayed source", editor.textView.string == "External")
        check("a clean external reload clears stale Undo", !editor.coordinator.editorUndoManager.canUndo)
        check("a clean external reload clears stale Redo", !editor.coordinator.editorUndoManager.canRedo)
    }

    private static func testCharacterCountReports() {
        let first = NoteEditorInput(id: NoteID(rawValue: "First.md"), source: "First", epoch: 1)
        var reports: [(NoteEditorInput, Int)] = []
        let editor = makeEditor(input: first, onCountChange: { reports.append(($0, $1)) })
        check("installing a note reports its length", reports.last?.1 == 5)

        editor.textView.selectAll(nil)
        editor.textView.insertText("Twelve chars", replacementRange: editor.textView.selectedRange())
        check("typing reports the new length", reports.last?.1 == 12)

        editor.textView.selectAll(nil)
        editor.textView.insertText("🇬🇧", replacementRange: editor.textView.selectedRange())
        check(
            "the count is the text storage's own UTF-16 length",
            reports.last?.1 == editor.textView.textStorage?.length)

        let second = NoteEditorInput(id: NoteID(rawValue: "Second.md"), source: "Second", epoch: 2)
        editor.coordinator.parent = view(for: second, onCountChange: { reports.append(($0, $1)) })
        editor.coordinator.update(second)
        check(
            "a stale count cannot be attributed to the replacement note",
            reports.last?.0.id == second.id && reports.last?.1 == 6)
    }

    /// The primitives `copy:`/`cut:`/`paste:` delegate to; the actions clobber the real clipboard.
    private static func copySelection(of textView: NSTextView, to pasteboard: NSPasteboard) {
        let types = textView.writablePasteboardTypes
        pasteboard.declareTypes(types, owner: nil)
        _ = textView.writeSelection(to: pasteboard, types: types)
    }

    private static func cutSelection(of textView: NSTextView, to pasteboard: NSPasteboard) {
        copySelection(of: textView, to: pasteboard)
        textView.delete(nil)
    }

    private static func paste(
        _ text: String, into textView: NSTextView, from pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        _ = textView.readSelection(from: pasteboard)
    }

    private static func makeEditor(
        input: NoteEditorInput,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onCountChange: @escaping (NoteEditorInput, Int) -> Void = { _, _ in }
    ) -> (coordinator: NoteEditorView.Coordinator, textView: NoteTextView, window: NSWindow) {
        let view = view(
            for: input,
            onSourceChange: onSourceChange,
            onCountChange: onCountChange)
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        NoteEditorView.configure(textView)
        textView.delegate = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        textView.setFrameSize(NSSize(width: 320, height: 1))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: scrollView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.contentView = scrollView
        coordinator.textView = textView
        coordinator.install(input, resetUndo: false)
        window.makeFirstResponder(textView)
        return (coordinator, textView, window)
    }

    private static func view(
        for input: NoteEditorInput,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onCountChange: @escaping (NoteEditorInput, Int) -> Void = { _, _ in }
    ) -> NoteEditorView {
        NoteEditorView(
            input: input,
            onSourceChange: onSourceChange,
            onCharacterCountChange: onCountChange,
            onReady: { _ in })
    }

    private static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        guard condition() else {
            failures += 1
            print("FAIL: \(message)")
            return
        }
    }

    private static func keyDown(
        _ characters: String, keyCode: Int, modifiers: NSEvent.ModifierFlags = [.command],
        isARepeat: Bool = false, in window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: isARepeat, keyCode: UInt16(keyCode)) ?? NSEvent()
    }
}
