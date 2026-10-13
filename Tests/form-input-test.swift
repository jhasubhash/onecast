import AppKit
import SwiftUI

@main
@MainActor
struct FormInputTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        _ = NSApplication.shared
        testSingleLine()
        testCapAlignment()
        testTextArea()
        testCodeFont()
        testSubmit()
        testTextAreaFocusKeys()
        testSingleLineTextArea()
        testStaleSelection()
        testTextAreaSubmit()
        testCommandReturn()
        if failures > 0 { exit(1) }
        print("Form inputs passed")
    }

    static func window(content: NSView, height: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        return window
    }

    static func testSingleLine() {
        let draft = Draft()
        var backwards: Bool?
        let height = InterfaceMetrics.standard.size.formFieldHeight
        let hosting = NSHostingView(
            rootView: SingleLineFixture(draft: draft, moveFocus: { backwards = $0 })
                .frame(width: 300, height: height))
        let window = window(content: hosting, height: height)
        defer { window.close() }
        guard let input = find(FormTextInput.InputView.self, in: hosting),
            let cell = input.cell as? FormTextInput.InputCell
        else {
            expect(false, "single-line input mounts an NSTextField")
            return
        }
        expect(input.clipsToBounds, "the native field clips to its own bounds")
        expect(input.usesSingleLineMode, "AppKit owns single-line text behavior")
        expect(input.placeholderAttributedString?.string == "Placeholder", "placeholder is native")
        expect(input.accessibilityLabel() == "Test", "native input has an accessibility label")
        let frame = input.frame
        let rect = cell.contentRect(forBounds: input.bounds)
        expect(rect.minX == InterfaceMetrics.standard.spacing.xl, "text keeps its horizontal padding")
        let alignment = input.alignmentRectInsets
        expect(
            [alignment.top, alignment.bottom, alignment.left, alignment.right].allSatisfy { $0 == 0 },
            "the native field does not outgrow its chrome")
        let restingInk = inkBounds(hosting)
        expect(!restingInk.isNull, "the placeholder rendering test captures visible text")
        window.makeFirstResponder(input)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(inkBounds(hosting) == restingInk, "focusing never moves the rendered placeholder")
        expect(draft.focused, "taking first responder updates focus before typing")
        guard let editor = input.currentEditor() as? NSTextView else {
            expect(false, "AppKit supplies the single-line field editor")
            return
        }
        expect(editor.frame == rect, "resting text and field editor share the same rectangle")
        for _ in 0..<3 {
            editor.insertText("Test", replacementRange: NSRange(location: 0, length: 0))
            editor.setSelectedRange(NSRange(location: 0, length: 4))
            editor.deleteBackward(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            input.layoutSubtreeIfNeeded()
            expect(draft.name.isEmpty, "native typing and deletion update the binding")
            expect(input.frame == frame, "editing never resizes the single-line field")
            expect(editor.frame == rect, "deletion never moves the field editor")
            expect(
                cell.contentRect(forBounds: input.bounds) == rect, "empty placeholder keeps its origin"
            )
        }
        let delegate = input.delegate!
        expect(
            delegate.control?(input, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
                == true,
            "Tab goes through the form's focus order")
        expect(backwards == false, "Tab advances focus")
        _ = delegate.control?(input, textView: editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))
        expect(backwards == true, "Shift-Tab reverses focus")
        window.makeFirstResponder(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(inkBounds(hosting) == restingInk, "leaving the field never moves the rendered placeholder")
        expect(!draft.focused, "leaving the field clears focus")
        draft.name = "Placeholder"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(
            abs(inkBounds(hosting).minY - restingInk.minY) <= 1,
            "text and placeholder share the same rendered baseline")
    }

    static func testCapAlignment() {
        for scale: CGFloat in [1, 1.1, 1.2] {
            let metrics = InterfaceMetrics(scale: scale)
            let draft = Draft()
            draft.name = "H"
            let height = metrics.size.formFieldHeight
            let hosting = NSHostingView(
                rootView: SingleLineFixture(draft: draft, moveFocus: { _ in })
                    .environment(\.metrics, metrics).frame(width: 300, height: height))
            let window = window(content: hosting, height: height)
            let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            let pixelsPerPoint = CGFloat(image.pixelsHigh) / height
            let restingInk = inkBounds(hosting)
            let input = find(FormTextInput.InputView.self, in: hosting)!
            expect(
                abs(restingInk.midY / pixelsPerPoint - height / 2) <= 0.5,
                "capitals are vertically centered at scale \(scale)")
            window.makeFirstResponder(input)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            guard let editor = input.currentEditor() as? NSTextView else {
                expect(false, "cap-height test receives a native field editor")
                window.close()
                continue
            }
            editor.setSelectedRange(NSRange(location: 1, length: 0))
            expect(
                inkBounds(hosting) == restingInk,
                "editing preserves the cap-height alignment at scale \(scale)")
            let swiftUI = NSHostingView(
                rootView: Text("H").font(metrics.typography.rowTitle)
                    .foregroundStyle(.white).frame(width: 300, height: height))
            let other = Self.window(content: swiftUI, height: height)
            expect(
                abs(inkBounds(swiftUI).midY - restingInk.midY) <= 1,
                "native inputs align with SwiftUI picker text at scale \(scale)")
            other.close()
            window.close()
        }
    }

    static func inkBounds(_ view: NSView) -> CGRect {
        let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: image)
        var result = CGRect.null
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.alphaComponent > 0.2, color.redComponent > 0.2
                {
                    result = result.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return result
    }

    static func testTextArea() {
        let height: CGFloat = 120
        let draft = Draft()
        let hosting = NSHostingView(rootView: TextAreaFixture(draft: draft))
        let window = window(content: hosting, height: height)
        defer { window.close() }
        guard let input = find(FormTextArea.InputView.self, in: hosting) else {
            expect(false, "textarea mounts an NSTextView")
            return
        }
        expect(input.clipsToBounds, "textarea tracking stays inside its bounds")
        expect(input.isVerticallyResizable, "textarea grows instead of internally scrolling")
        expect(
            input.textContainerInset.height == InterfaceMetrics.standard.spacing.md,
            "textarea keeps its top padding")
        expect(input.textLayoutManager != nil, "textarea uses TextKit 2")
        expect(input.enclosingScrollView == nil, "textarea has no internal scroll view")
        expect(input.accessibilityLabel() == "Template", "textarea has an accessibility label")
        expect(input.undoManager?.canUndo == false, "loading a draft creates no undo step")
        window.makeFirstResponder(input)
        input.insertText("Undo check", replacementRange: NSRange(location: 0, length: 0))
        let previous = input.string
        draft.text = String(repeating: "A long line to wrap in the editor.\n", count: 40)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        hosting.layoutSubtreeIfNeeded()
        expect(
            find(FormTextArea.InputView.self, in: hosting) === input,
            "binding updates preserve native view identity")
        expect(hosting.fittingSize.height > height, "long content expands the textarea")
        expect(input.undoManager?.canUndo == true, "programmatic insertion uses native undo")
        let undo = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "z",
            charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        expect(input.performKeyEquivalent(with: undo), "the focused textarea handles Command-Z")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(input.string == previous, "undo restores the content before programmatic insertion")
        expect(draft.text == previous, "native undo reaches the binding")
        let redo = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "Z",
            charactersIgnoringModifiers: "Z", isARepeat: false, keyCode: 6)!
        expect(input.performKeyEquivalent(with: redo), "the focused textarea handles Command-Shift-Z")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(draft.text == input.string && draft.text != previous, "native redo reaches the binding")
        input.undoManager?.undo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        window.makeFirstResponder(nil)
        draft.text += "{date}"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        input.undoManager?.undo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(draft.text == previous, "placeholder insertion remains undoable after a menu takes focus")
        let value = "Avant 👋{date} après"
        let caret = value.index(value.startIndex, offsetBy: 13)
        draft.text = value
        draft.selection = TextSelection(range: caret..<caret)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        hosting.layoutSubtreeIfNeeded()
        expect(
            input.selectedRange() == NSRange(caret..<caret, in: value),
            "programmatic insertion restores the Unicode caret, not the end of the textarea")
        expect(hosting.fittingSize.height <= height, "deletion shrinks the textarea to its minimum")
        input.undoManager?.redo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(draft.text == input.string, "native redo stays synchronized with the binding")
    }

    static func testCodeFont() {
        let draft = Draft()
        let hosting = NSHostingView(rootView: TextAreaFixture(draft: draft, isCode: true))
        let window = window(content: hosting, height: 120)
        defer { window.close() }
        let font = find(FormTextArea.InputView.self, in: hosting)?.font
        expect(
            font
                == NSFont.monospacedSystemFont(
                    ofSize: InterfaceMetrics.standard.typography.nsFont(.body).pointSize, weight: .regular
                ),
            "code textareas use the native monospaced font at the shared body size")
        let input = find(FormTextArea.InputView.self, in: hosting)
        expect(
            input?.isAutomaticQuoteSubstitutionEnabled == false
                && input?.isAutomaticDashSubstitutionEnabled == false
                && input?.isAutomaticTextReplacementEnabled == false
                && input?.isAutomaticSpellingCorrectionEnabled == false,
            "code textareas do not rewrite shell syntax while typing")
    }

    static func testSubmit() {
        let draft = Draft()
        let height = InterfaceMetrics.standard.size.formFieldHeight
        let hosting = NSHostingView(
            rootView: SingleLineFixture(draft: draft, moveFocus: { _ in }).frame(width: 300, height: height))
        let window = window(content: hosting, height: height)
        defer { window.close() }
        guard let input = find(FormTextInput.InputView.self, in: hosting),
            let delegate = input.delegate
        else {
            expect(false, "single-line input mounts an NSTextField with a delegate")
            return
        }
        window.makeFirstResponder(input)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        guard let editor = input.currentEditor() as? NSTextView else {
            expect(false, "AppKit supplies the single-line field editor")
            return
        }
        let newline = #selector(NSResponder.insertNewline(_:))
        expect(
            delegate.control?(input, textView: editor, doCommandBy: newline) == false,
            "Return keeps AppKit's default when nothing submits")
        expect(draft.submits == 0, "no submit closure, no submit")
        draft.submitsOnReturn = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(
            delegate.control?(input, textView: editor, doCommandBy: newline) == true,
            "Return is consumed once a submit closure arrives with a view update")
        expect(draft.submits == 1, "Return calls the submit closure once")
        editor.insertText("kept", replacementRange: NSRange(location: 0, length: 0))
        editor.doCommand(by: newline)
        expect(draft.submits == 2, "the field editor's own Return command reaches the submit closure")
        expect(editor.string == "kept" && draft.name == "kept", "submitting never edits the text")
        let other = #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        expect(
            delegate.control?(input, textView: editor, doCommandBy: other) == false,
            "only plain Return submits")
        draft.submitsOnReturn = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(
            delegate.control?(input, textView: editor, doCommandBy: newline) == false,
            "removing the submit closure restores AppKit's Return")
        expect(draft.submits == 2, "a removed submit closure is never called")
    }

    static func testTextAreaFocusKeys() {
        let draft = Draft()
        var backwards: Bool?
        let hosting = NSHostingView(
            rootView: TextAreaFixture(draft: draft, moveFocus: { backwards = $0 }))
        let window = window(content: hosting, height: 120)
        defer { window.close() }
        guard let input = find(FormTextArea.InputView.self, in: hosting) else {
            expect(false, "textarea mounts an NSTextView")
            return
        }
        window.makeFirstResponder(input)
        input.doCommand(by: #selector(NSResponder.insertTab(_:)))
        expect(backwards == false, "Tab advances the form's focus from a textarea")
        input.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        expect(backwards == true, "Shift-Tab reverses the form's focus from a textarea")
        expect(input.string.isEmpty, "Tab walks the form instead of typing a tab")
        input.doCommand(by: #selector(NSResponder.insertTabIgnoringFieldEditor(_:)))
        expect(input.string == "\t" && draft.text == "\t", "Option-Tab types a literal tab")
        let optionTab = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\t",
            charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        input.keyDown(with: optionTab)
        expect(draft.text == "\t\t", "the Option-Tab chord reaches the tab command")
        input.insertText("a\nb", replacementRange: input.selectedRange())
        expect(draft.text == "\t\ta\nb", "a multi-line textarea keeps typed line breaks")
        input.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        expect(draft.text == "\t\ta\nb\n", "Return inserts a newline in a multi-line textarea")
        let pasted = pastedText("one\ntwo", into: input, replacing: NSRange(location: 0, length: 0))
        expect(pasted == "one\ntwo\t\ta\nb\n", "a multi-line textarea keeps pasted line breaks")
    }

    static func testSingleLineTextArea() {
        let draft = Draft()
        let hosting = NSHostingView(rootView: TextAreaFixture(draft: draft, allowsLineBreaks: false))
        let window = window(content: hosting, height: 120)
        defer { window.close() }
        guard let input = find(FormTextArea.InputView.self, in: hosting),
            let delegate = input.delegate
        else {
            expect(false, "textarea mounts an NSTextView with a delegate")
            return
        }
        window.makeFirstResponder(input)
        input.insertText("link", replacementRange: NSRange(location: 0, length: 0))
        let commands = [
            #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
            #selector(NSResponder.insertParagraphSeparator(_:)),
        ]
        for command in commands {
            expect(
                delegate.textView?(input, doCommandBy: command) == true,
                "a one-line textarea swallows \(command)")
            input.doCommand(by: command)
        }
        expect(input.string == "link" && draft.text == "link", "newline commands never reach the text")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        input.breakUndoCoalescing()
        input.setSelectedRange(NSRange(location: 4, length: 0))
        expect(
            pastedText("one\ntwo", into: input, replacing: input.selectedRange()) == "linkone two",
            "a pasted line break becomes a space")
        expect(draft.text == "linkone two", "the flattened paste reaches the binding")
        expect(
            input.selectedRange() == NSRange(location: 11, length: 0),
            "the caret follows the flattened paste")
        input.undoManager?.undo()
        expect(input.string == "link", "a flattened paste undoes as one step")

        expect(
            pastedText("a\r\nb\n\n\nc", into: input, replacing: NSRange(location: 0, length: 4)) == "a b c",
            "CRLF and runs of breaks collapse to one space and replace the selection")
        expect(
            pastedText("https://x.test/p\n", into: input, replacing: NSRange(location: 0, length: 1))
                == "https://x.test/p b c",
            "a trailing newline from copying a whole line never leaves a space")
        let settled = input.string
        expect(
            pastedText("\n\r\n", into: input, replacing: NSRange(location: 0, length: 5)) == settled,
            "a paste of only line breaks changes nothing")
        expect(draft.text == settled, "a rejected paste leaves the binding alone")

        input.insertText("x\u{2028}y", replacementRange: NSRange(location: 0, length: 0))
        expect(
            input.string.hasPrefix("x y") && !input.string.contains("\u{2028}"),
            "a Unicode line separator is flattened too")

        draft.text = "kept\nas\ngiven"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(input.string == "kept\nas\ngiven", "a value set by the model is shown as given")
        expect(draft.text == "kept\nas\ngiven", "showing a model value never rewrites it")
    }

    static func testStaleSelection() {
        let draft = Draft()
        let hosting = NSHostingView(rootView: TextAreaFixture(draft: draft))
        let window = window(content: hosting, height: 120)
        defer { window.close() }
        guard let input = find(FormTextArea.InputView.self, in: hosting) else {
            expect(false, "textarea mounts an NSTextView")
            return
        }
        window.makeFirstResponder(input)
        input.insertText("a rather long line of text", replacementRange: NSRange(location: 0, length: 0))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(draft.selection != nil, "typing records the caret in the selection binding")
        draft.text = "ab"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(input.string == "ab", "a shorter model value replaces the text")
        expect(
            input.selectedRange() == NSRange(location: 2, length: 0),
            "a selection from the replaced text puts the caret at the end instead of trapping")
    }

    static func testTextAreaSubmit() {
        let commands = [
            #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
            #selector(NSResponder.insertParagraphSeparator(_:)),
        ]
        let single = Draft()
        let area = NSHostingView(rootView: TextAreaFixture(draft: single, allowsLineBreaks: false))
        let window = window(content: area, height: 120)
        defer { window.close() }
        guard let input = find(FormTextArea.InputView.self, in: area) else {
            expect(false, "textarea mounts an NSTextView")
            return
        }
        window.makeFirstResponder(input)
        input.insertText("link", replacementRange: NSRange(location: 0, length: 0))
        for command in commands { input.doCommand(by: command) }
        expect(single.submits == 0, "a one-line textarea without onSubmit just ignores Return")
        single.submitsOnReturn = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        for command in commands { input.doCommand(by: command) }
        expect(single.submits == commands.count, "every newline command submits a one-line textarea")
        expect(input.string == "link" && single.text == "link", "submitting never edits the text")

        let multi = Draft()
        multi.submitsOnReturn = true
        let lines = NSHostingView(rootView: TextAreaFixture(draft: multi))
        let other = Self.window(content: lines, height: 120)
        defer { other.close() }
        guard let multiInput = find(FormTextArea.InputView.self, in: lines) else {
            expect(false, "multi-line textarea mounts an NSTextView")
            return
        }
        other.makeFirstResponder(multiInput)
        multiInput.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        expect(multi.submits == 0, "a multi-line textarea never submits")
        expect(multi.text == "\n", "a multi-line textarea still inserts the newline")
    }

    static func testCommandReturn() {
        let command = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36)!
        let draft = Draft()
        draft.submitsOnReturn = true
        let field = NSHostingView(
            rootView: SingleLineFixture(draft: draft, moveFocus: { _ in }).frame(width: 300, height: 34))
        let area = NSHostingView(rootView: TextAreaFixture(draft: draft, allowsLineBreaks: false))
        for (name, hosting) in [("field", field), ("textarea", area)] {
            let sentinel = ChordSentinel()
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            hosting.frame = container.bounds
            container.addSubview(hosting)
            container.addSubview(sentinel)
            let window = window(content: container, height: 120)
            defer { window.close() }
            let responder: NSView? =
                find(FormTextInput.InputView.self, in: hosting)
                ?? find(FormTextArea.InputView.self, in: hosting)
            guard let responder else {
                expect(false, "the \(name) mounts a native responder")
                continue
            }
            window.makeFirstResponder(responder)
            let owner = (responder as? NSTextField)?.currentEditor() ?? responder
            expect(!owner.performKeyEquivalent(with: command), "the focused \(name) leaves ⌘↵ alone")
            expect(!responder.performKeyEquivalent(with: command), "the \(name) view leaves ⌘↵ alone")
            expect(window.performKeyEquivalent(with: command), "⌘↵ from a \(name) reaches the window")
            expect(sentinel.received == 1, "⌘↵ from a \(name) reaches a sibling's key equivalent")
        }
    }

    static func pastedText(_ string: String, into input: NSTextView, replacing range: NSRange) -> String {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        input.setSelectedRange(range)
        _ = input.readSelection(from: pasteboard, type: .string)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        return input.string
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let input = view as? T { return input }
        for child in view.subviews {
            if let input = find(type, in: child) { return input }
        }
        return nil
    }

    @Observable
    final class Draft {
        var text = ""
        var selection: TextSelection?
        var name = ""
        var focused = false
        var submitsOnReturn = false
        var submits = 0
    }

    final class ChordSentinel: NSView {
        var received = 0

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.contains(.command), event.keyCode == 36 else { return false }
            received += 1
            return true
        }
    }

    struct SingleLineFixture: View {
        @Bindable var draft: Draft
        var moveFocus: (Bool) -> Void

        var body: some View {
            FormTextInput(
                text: $draft.name, focused: $draft.focused,
                placeholder: "Placeholder", label: "Test", moveFocus: moveFocus,
                onSubmit: draft.submitsOnReturn ? { draft.submits += 1 } : nil)
        }
    }

    struct TextAreaFixture: View {
        @Bindable var draft: Draft
        var isCode = false
        var allowsLineBreaks = true
        var moveFocus: (Bool) -> Void = { _ in }

        var body: some View {
            FormTextArea(
                text: $draft.text, selection: $draft.selection, focused: .constant(false),
                minimumHeight: 120, label: "Template", isCode: isCode,
                allowsLineBreaks: allowsLineBreaks,
                onSubmit: draft.submitsOnReturn ? { draft.submits += 1 } : nil, moveFocus: moveFocus
            ).frame(width: 300)
        }
    }
}
