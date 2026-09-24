import AppKit
import SwiftUI

/// A reply's markdown in one native text view, so a drag selects across every block of it.
struct MarkdownView: NSViewRepresentable {
    @Environment(\.metrics) private var metrics
    let markdown: String
    var color: Color = Theme.Colors.textPrimary

    func makeNSView(context: Context) -> MarkdownTextView {
        MarkdownTextView()
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        view.show(MarkdownTextView.Content(markdown: markdown, color: color, metrics: metrics))
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView view: MarkdownTextView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: view.height(forWidth: width))
    }
}

/// TextKit 1 on purpose: tables and cards are `NSTextTable`/`NSTextBlock`, absent from TextKit 2.
final class MarkdownTextView: NSTextView {
    struct Content: Equatable {
        let markdown: String
        let color: Color
        let metrics: InterfaceMetrics
    }

    /// The one reply holding a selection; starting a new one clears it, as a browser page does.
    private static weak var selectionOwner: MarkdownTextView?

    private var content: Content?
    private var copyButtons: [(block: MarkdownCodeBlock, view: NSHostingView<AnyView>)] = []

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Re-rendered only when something drawn changes; a streaming reply keeps its selection.
    func show(_ next: Content) {
        guard next != content, let storage = textStorage else { return }
        content = next
        let rendered = MarkdownRenderer.render(
            MarkdownBlock.parse(next.markdown), style: Self.style(next.color, next.metrics))
        let selection = selectedRange()
        storage.setAttributedString(rendered)
        if NSMaxRange(selection) <= rendered.length { setSelectedRange(selection) }
        syncCopyButtons(next.metrics)
        needsLayout = true
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        guard let container = textContainer, let layout = layoutManager else { return 0 }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height)
    }

    // MARK: - Copying

    /// Plain text only: rich text would carry this appearance's ink into the app it lands in.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string, let storage = textStorage else { return false }
        let selected = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        let text = selected.map { MarkdownRenderer.plainText(storage.attributedSubstring(from: $0)) }
        return pboard.setString(text.joined(separator: "\n"), forType: .string)
    }

    /// ⌘C while the keyboard stays in a composer: copy the reply selection in `window`, if any.
    static func copySelection(in window: NSWindow) -> Bool {
        guard let owner = selectionOwner, owner.window === window, owner.selectedRange().length > 0
        else { return false }
        owner.copy(nil)
        return true
    }

    // MARK: - Keyboard focus

    /// Only a click may focus a reply: never initial focus, Tab, or a window's own pick.
    private var trackingClick = false

    override var acceptsFirstResponder: Bool { trackingClick }

    override func mouseDown(with event: NSEvent) {
        if let owner = Self.selectionOwner, owner !== self {
            owner.setSelectedRange(NSRange(location: owner.selectedRange().location, length: 0))
        }
        Self.selectionOwner = self
        returningKeyboardFocus { super.mouseDown(with: event) }
    }

    override func rightMouseDown(with event: NSEvent) {
        returningKeyboardFocus { super.rightMouseDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        if let menu { Self.target(menu, at: self) }
        return menu
    }

    /// Focus is back in the composer before a picked item fires, so each must name this view.
    private static func target(_ menu: NSMenu, at view: NSTextView) {
        for item in menu.items {
            if item.target == nil, item.action != nil { item.target = view }
            if let submenu = item.submenu { target(submenu, at: view) }
        }
    }

    /// Keeps typing, ↵ and ⎋ in the composer, caret and all, rather than in read-only text.
    private func returningKeyboardFocus(_ track: () -> Void) {
        let editor = window?.firstResponder as? NSTextView
        let caret = editor?.selectedRanges
        // A field editor answers for its text field, which is what has to take focus back.
        let previous = (editor?.delegate as? NSView) ?? (window?.firstResponder as? NSView)
        trackingClick = true
        track()
        trackingClick = false
        guard let window, window.firstResponder === self, let previous, previous !== self,
            window.makeFirstResponder(previous)
        else { return }
        if let caret, let restored = window.firstResponder as? NSTextView {
            restored.selectedRanges = caret
        }
    }

    // MARK: - Code copy buttons

    override func layout() {
        super.layout()
        placeCopyButtons()
    }

    /// One per code card, reused across a stream so a pressed button keeps its checkmark.
    private func syncCopyButtons(_ metrics: InterfaceMetrics) {
        let blocks = codeBlocks()
        while copyButtons.count > blocks.count { copyButtons.removeLast().view.removeFromSuperview() }
        for (index, block) in blocks.enumerated() {
            let button = AnyView(ChatCopyButton(text: block.source, subject: "Code").environment(\.metrics, metrics))
            if index < copyButtons.count {
                copyButtons[index].block = block
                copyButtons[index].view.rootView = button
            } else {
                let host = NSHostingView(rootView: button)
                addSubview(host)
                copyButtons.append((block, host))
            }
        }
    }

    private func codeBlocks() -> [MarkdownCodeBlock] {
        guard let storage = textStorage else { return [] }
        var blocks: [MarkdownCodeBlock] = []
        storage.enumerateAttribute(
            .paragraphStyle, in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            let style = value as? NSParagraphStyle
            for case let block as MarkdownCodeBlock in style?.textBlocks ?? []
            where !blocks.contains(where: { $0 === block }) {
                blocks.append(block)
            }
        }
        return blocks
    }

    /// Top-trailing inside the card's padding, where the SwiftUI card put its header button.
    private func placeCopyButtons() {
        guard let layout = layoutManager, let storage = textStorage else { return }
        for (block, host) in copyButtons {
            guard let character = firstCharacter(of: block, in: storage) else { continue }
            let glyph = layout.glyphIndexForCharacter(at: character)
            let frame = layout.boundsRect(for: block, at: glyph, effectiveRange: nil)
            let card = block.cardRect(in: frame)
            let size = host.fittingSize
            host.frame = NSRect(
                x: card.maxX - block.width(for: .padding, edge: .maxX) - size.width,
                y: card.minY + block.width(for: .padding, edge: .maxY),
                width: size.width, height: size.height)
        }
    }

    private func firstCharacter(of block: MarkdownCodeBlock, in storage: NSTextStorage) -> Int? {
        var found: Int?
        storage.enumerateAttribute(
            .paragraphStyle, in: NSRange(location: 0, length: storage.length)
        ) { value, range, stop in
            guard (value as? NSParagraphStyle)?.textBlocks.contains(where: { $0 === block }) == true
            else { return }
            found = range.location
            stop.pointee = true
        }
        return found
    }

    // MARK: - Style

    private static func style(_ color: Color, _ metrics: InterfaceMetrics) -> MarkdownTextStyle {
        let type = metrics.typography
        let body = type.nsFont(.body)
        return MarkdownTextStyle(
            body: body,
            headings: [
                .systemFont(ofSize: type.nsFont(.title2).pointSize, weight: .semibold),
                .systemFont(ofSize: type.nsFont(.title3).pointSize, weight: .semibold),
                type.nsFont(.headline),
            ],
            code: .monospacedSystemFont(ofSize: type.nsFont(.callout).pointSize, weight: .regular),
            inlineCode: .monospacedSystemFont(ofSize: body.pointSize, weight: .regular),
            tableHeader: .systemFont(ofSize: type.nsFont(.subheadline).pointSize, weight: .medium),
            codeLabel: type.nsFont(.caption1),
            text: NSColor(color),
            secondary: NSColor(Theme.Colors.textSecondary),
            tertiary: NSColor(Theme.Colors.textTertiary),
            checked: NSColor(Theme.Colors.success),
            inlineCodeFill: NSColor(Theme.Colors.controlSurface),
            cardFill: NSColor(Theme.Colors.cardFill),
            cardStroke: NSColor(Theme.Colors.cardStroke),
            quoteBar: NSColor(Theme.Colors.border),
            blockGap: metrics.spacing.lg,
            headingGap: metrics.spacing.sm,
            itemGap: metrics.spacing.xs,
            markerWidth: metrics.size.markdownListMarker,
            markerGap: metrics.spacing.sm,
            cardInset: CGSize(width: metrics.spacing.xl, height: metrics.spacing.lg),
            cardRadius: metrics.radius.card,
            codeHeader: metrics.size.chatMessageAction + metrics.spacing.sm,
            quoteBarWidth: metrics.size.markdownQuoteBar,
            quoteGap: metrics.spacing.lg,
            tableColumnGap: metrics.spacing.xl,
            tableRowGap: metrics.spacing.sm,
            hairline: Theme.Size.hairline)
    }
}
