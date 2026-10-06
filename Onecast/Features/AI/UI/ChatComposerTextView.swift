import AppKit
import SwiftUI

/// The window's composer field: Return sends, ⇧↩ breaks the line, and it grows to a cap.
struct ChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    /// A new value pulls focus into the field: a switched chat is one you are about to type into.
    let focusKey: UUID
    let maximumTextHeight: CGFloat
    let handle: ComposerTextViewHandle
    let onInvalidate: (ComposerTextView) -> Void
    /// Asked first for arrows, Return and Escape; true means an open menu took the key.
    let onMenuKey: (KeyEquivalent) -> Bool
    let onSubmit: () -> Void

    private static var font: NSFont { .systemFont(ofSize: 16) }

    static var lineHeight: CGFloat {
        (font.ascender - font.descender + font.leading).rounded(.up)
    }

    static func textHeight(_ text: String, width: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        // A trailing newline starts a line `boundingRect` would not count until it held a glyph.
        let measured = (text.hasSuffix("\n") ? text + " " : text) as NSString
        let height = measured.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
        ).height.rounded(.up)
        return min(max(lineHeight, height), maximumHeight)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text, onInvalidate: onInvalidate, onMenuKey: onMenuKey, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ComposerTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? ComposerTextView else { return scroll }
        handle.textView = textView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.setAccessibilityLabel("Message")
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? ComposerTextView else { return }
        if context.coordinator.focusedKey != focusKey { onInvalidate(textView) }
        context.coordinator.text = $text
        context.coordinator.onInvalidate = onInvalidate
        context.coordinator.onMenuKey = onMenuKey
        context.coordinator.onSubmit = onSubmit
        // Only an outside write lands here; echoing the view's own text back would reset the caret.
        if textView.string != text { textView.string = text }
        guard context.coordinator.focusedKey != focusKey else { return }
        context.coordinator.focusedKey = focusKey
        // Next turn: on first mount the view has no window to become first responder of yet.
        Task { @MainActor [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let textView = scroll.documentView as? ComposerTextView else { return }
        coordinator.onInvalidate(textView)
        textView.isEditable = false
        textView.delegate = nil
    }

    /// Measured from the text rather than the text view, whose width lags the proposal by a pass.
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSScrollView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(
            width: width,
            height: Self.textHeight(text, width: width, maximumHeight: maximumTextHeight))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onInvalidate: (ComposerTextView) -> Void
        var onMenuKey: (KeyEquivalent) -> Bool
        var onSubmit: () -> Void
        var focusedKey: UUID?

        init(
            text: Binding<String>, onInvalidate: @escaping (ComposerTextView) -> Void,
            onMenuKey: @escaping (KeyEquivalent) -> Bool, onSubmit: @escaping () -> Void
        ) {
            self.text = text
            self.onInvalidate = onInvalidate
            self.onMenuKey = onMenuKey
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        /// Never called mid-composition, so Return confirming an input method's text stays its own.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): return onMenuKey(.upArrow)
            case #selector(NSResponder.moveDown(_:)): return onMenuKey(.downArrow)
            case #selector(NSResponder.cancelOperation(_:)): return onMenuKey(.escape)
            case #selector(NSResponder.insertNewline(_:)):
                if onMenuKey(.return) { return true }
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    onSubmit()
                }
                return true
            default:
                return false
            }
        }
    }
}

/// Onecast's own editor, so dictation, snippets and Quick Actions write into it in process.
final class ComposerTextView: NSTextView, InjectableTextView {}

/// How a control beside the field reaches the text view the representable made.
@MainActor
final class ComposerTextViewHandle {
    weak var textView: ComposerTextView?
}
