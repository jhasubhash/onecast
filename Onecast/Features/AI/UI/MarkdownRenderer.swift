import AppKit

/// Everything a rendered reply is drawn with, resolved from the theme by `MarkdownView`.
struct MarkdownTextStyle {
    var body: NSFont
    /// Levels 1, 2 and 3; deeper headings take the last.
    var headings: [NSFont]
    var code: NSFont
    var inlineCode: NSFont
    var tableHeader: NSFont
    var codeLabel: NSFont
    var text: NSColor
    var secondary: NSColor
    var tertiary: NSColor
    var checked: NSColor
    var inlineCodeFill: NSColor
    var cardFill: NSColor
    var cardStroke: NSColor
    var quoteBar: NSColor
    var blockGap: CGFloat
    var headingGap: CGFloat
    var itemGap: CGFloat
    var markerWidth: CGFloat
    var markerGap: CGFloat
    var cardInset: CGSize
    var cardRadius: CGFloat
    /// Room above a code block's text for its language label and copy button.
    var codeHeader: CGFloat
    var quoteBarWidth: CGFloat
    var quoteGap: CGFloat
    var tableColumnGap: CGFloat
    var tableRowGap: CGFloat
    var hairline: CGFloat
}

extension NSAttributedString.Key {
    /// On a run a copy writes differently from how it draws: a list marker's tabs, a cell's break.
    static let markdownCopyText = NSAttributedString.Key("OnecastMarkdownCopyText")
}

/// One reply as one attributed string, so a single text view can select across every block of it.
enum MarkdownRenderer {
    static func render(_ blocks: [MarkdownBlock], style: MarkdownTextStyle) -> NSAttributedString {
        var builder = Builder(style: style)
        builder.blocks(blocks, Builder.Context(color: style.text), first: 0, between: style.blockGap)
        return builder.finished()
    }

    /// What a copy of `text` puts on the pasteboard: markers as typed, table cells tab-separated.
    static func plainText(_ text: NSAttributedString) -> String {
        var plain = ""
        let source = text.string as NSString
        text.enumerateAttribute(
            .markdownCopyText, in: NSRange(location: 0, length: text.length)
        ) { value, range, _ in
            plain += (value as? String) ?? source.substring(with: range)
        }
        return plain.replacingOccurrences(of: "\u{2028}", with: "\n")
    }
}

private struct Builder {
    struct Context {
        var indent: CGFloat = 0
        var depth = 0
        var textBlocks: [NSTextBlock] = []
        var color: NSColor
    }

    let style: MarkdownTextStyle
    private let text = NSMutableAttributedString()

    init(style: MarkdownTextStyle) {
        self.style = style
    }

    func finished() -> NSAttributedString {
        // Every paragraph ends in a break; the reply's last one has nothing after it to separate.
        if text.string.hasSuffix("\n") {
            text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
        }
        return text
    }

    mutating func blocks(_ blocks: [MarkdownBlock], _ context: Context, first: CGFloat, between: CGFloat) {
        for (offset, block) in blocks.enumerated() {
            var gap = offset == 0 ? first : between
            if offset > 0, case .heading = block { gap += style.headingGap }
            self.block(block, context, gap: gap)
        }
    }

    private mutating func block(_ block: MarkdownBlock, _ context: Context, gap: CGFloat) {
        switch block {
        case .heading(let level, let source):
            let font = style.headings[min(max(level, 1), style.headings.count) - 1]
            paragraph(inline(source, font: font, color: context.color), context, gap: gap)
        case .paragraph(let source):
            paragraph(inline(source, font: style.body, color: context.color), context, gap: gap)
        case .bulletList(let items):
            list(items, start: nil, context, gap: gap)
        case .numberedList(let start, let items):
            list(items, start: start, context, gap: gap)
        case .code(let language, let source):
            code(source, language: language, context, gap: gap)
        case .quote(let inner):
            let quote = MarkdownQuoteBlock(color: style.quoteBar, width: style.quoteBarWidth)
            quote.setWidth(style.quoteBarWidth + style.quoteGap, type: .absoluteValueType, for: .padding, edge: .minX)
            var nested = enter(quote, context, gap: gap)
            nested.color = style.secondary
            blocks(inner, nested, first: 0, between: style.blockGap)
        case .table(let table):
            self.table(table, context, gap: gap)
        case .rule:
            let rule = MarkdownRuleBlock(color: style.cardStroke, thickness: style.hairline)
            let nested = enter(rule, context, gap: gap)
            // A short line, so the rule takes only the air around it rather than a full text line.
            let font = NSFont.systemFont(ofSize: max(1, style.blockGap))
            paragraph(NSAttributedString(string: ""), nested, gap: 0, breakFont: font)
        }
    }

    /// Markers sit on a right tab and wrapped lines hang at the text, as a typeset list does.
    private mutating func list(
        _ items: [MarkdownBlock.Item], start: Int?, _ context: Context, gap: CGFloat
    ) {
        let markerEnd = context.indent + style.markerWidth
        let contentStart = markerEnd + style.markerGap
        var inner = context
        inner.indent = contentStart
        inner.depth += 1
        for (offset, item) in items.enumerated() {
            let itemGap = offset == 0 ? gap : style.itemGap
            let line = NSMutableAttributedString(attributedString: marker(item, offset, start, items.count, context))
            var rest = item.blocks[...]
            if case .paragraph(let source) = rest.first {
                line.append(inline(source, font: style.body, color: context.color))
                rest = rest.dropFirst()
            }
            paragraph(line, context, gap: itemGap) { paragraph in
                paragraph.headIndent = contentStart
                paragraph.tabStops = [
                    NSTextTab(textAlignment: .right, location: markerEnd),
                    NSTextTab(textAlignment: .left, location: contentStart),
                ]
            }
            blocks(Array(rest), inner, first: style.itemGap, between: style.itemGap)
        }
    }

    private func marker(
        _ item: MarkdownBlock.Item, _ offset: Int, _ start: Int?, _ count: Int, _ context: Context
    ) -> NSAttributedString {
        let glyph: String
        var color = style.secondary
        if let checked = item.checked {
            glyph = checked ? "☑" : "☐"
            color = checked ? style.checked : style.tertiary
        } else if let start {
            glyph = "\(start + offset)."
        } else {
            glyph = "•"
        }
        let copied = String(repeating: "    ", count: context.depth) + glyph + " "
        let font = start == nil ? style.body : monospacedDigits(style.body)
        return NSAttributedString(
            string: "\t\(glyph)\t",
            attributes: [.font: font, .foregroundColor: color, .markdownCopyText: copied])
    }

    private mutating func code(_ source: String, language: String?, _ context: Context, gap: CGFloat) {
        let card = MarkdownCodeBlock(
            source: source, language: language, label: style.codeLabel, labelColor: style.tertiary,
            fill: style.cardFill, stroke: style.cardStroke, radius: style.cardRadius)
        card.setWidth(style.cardInset.width, type: .absoluteValueType, for: .padding, edge: .minX)
        card.setWidth(style.cardInset.width, type: .absoluteValueType, for: .padding, edge: .maxX)
        card.setWidth(
            style.cardInset.height + style.codeHeader, type: .absoluteValueType, for: .padding, edge: .minY)
        card.setWidth(style.cardInset.height, type: .absoluteValueType, for: .padding, edge: .maxY)
        let nested = enter(card, context, gap: gap)
        for line in source.components(separatedBy: "\n") {
            let run = NSAttributedString(
                string: line, attributes: [.font: style.code, .foregroundColor: context.color])
            paragraph(run, nested, gap: 0, breakFont: style.code)
        }
    }

    private mutating func table(_ table: MarkdownBlock.Table, _ context: Context, gap: CGFloat) {
        let columns = table.header.count
        let grid = MarkdownTableBlock(fill: style.cardFill, stroke: style.cardStroke, radius: style.cardRadius)
        grid.numberOfColumns = columns
        grid.layoutAlgorithm = .automaticLayoutAlgorithm
        grid.collapsesBorders = true
        let inset = CGSize(
            width: style.cardInset.width - style.tableColumnGap / 2,
            height: style.cardInset.width - style.tableRowGap / 2)
        grid.setWidth(inset.width, type: .absoluteValueType, for: .padding, edge: .minX)
        grid.setWidth(inset.width, type: .absoluteValueType, for: .padding, edge: .maxX)
        grid.setWidth(inset.height, type: .absoluteValueType, for: .padding, edge: .minY)
        grid.setWidth(inset.height, type: .absoluteValueType, for: .padding, edge: .maxY)
        grid.setWidth(gap, type: .absoluteValueType, for: .margin, edge: .minY)
        grid.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        for (row, cells) in ([table.header] + table.rows).enumerated() {
            for column in 0..<columns {
                let cell = NSTextTableBlock(
                    table: grid, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setWidth(style.tableColumnGap / 2, type: .absoluteValueType, for: .padding, edge: .minX)
                cell.setWidth(style.tableColumnGap / 2, type: .absoluteValueType, for: .padding, edge: .maxX)
                cell.setWidth(style.tableRowGap / 2, type: .absoluteValueType, for: .padding, edge: .minY)
                cell.setWidth(style.tableRowGap / 2, type: .absoluteValueType, for: .padding, edge: .maxY)
                if row == 0 {
                    cell.setWidth(style.hairline, type: .absoluteValueType, for: .border, edge: .maxY)
                    cell.setBorderColor(style.cardStroke, for: .maxY)
                }
                let header = row == 0
                let content = inline(
                    column < cells.count ? cells[column] : "",
                    font: header ? style.tableHeader : style.body,
                    color: header ? style.secondary : context.color)
                var nested = context
                nested.indent = 0
                nested.textBlocks = context.textBlocks + [cell]
                let alignment = Self.alignment(table.alignments[column])
                // Tab between cells, so a pasted row lands in a spreadsheet's columns.
                let copied = column < columns - 1 ? "\t" : nil
                paragraph(content, nested, gap: 0, breakCopy: copied) { $0.alignment = alignment }
            }
        }
    }

    private static func alignment(_ alignment: MarkdownBlock.Table.Alignment) -> NSTextAlignment {
        switch alignment {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
    }

    /// A block's own margin carries the gap and the indent, so the text inside starts flush.
    private func enter(_ block: NSTextBlock, _ context: Context, gap: CGFloat) -> Context {
        // Without a content width a block lays out zero wide and AppKit never asks it to draw.
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(gap, type: .absoluteValueType, for: .margin, edge: .minY)
        block.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        var nested = context
        nested.indent = 0
        nested.textBlocks = context.textBlocks + [block]
        return nested
    }

    private mutating func paragraph(
        _ content: NSAttributedString, _ context: Context, gap: CGFloat, breakFont: NSFont? = nil,
        breakCopy: String? = nil, configure: (NSMutableParagraphStyle) -> Void = { _ in }
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = gap
        paragraph.firstLineHeadIndent = context.indent
        paragraph.headIndent = context.indent
        paragraph.textBlocks = context.textBlocks
        configure(paragraph)
        let line = NSMutableAttributedString(attributedString: content)
        var breakAttributes: [NSAttributedString.Key: Any] = [.font: breakFont ?? style.body]
        if let breakCopy { breakAttributes[.markdownCopyText] = breakCopy }
        line.append(NSAttributedString(string: "\n", attributes: breakAttributes))
        line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
        text.append(line)
    }

    /// Emphasis, code, strikethrough and links; a soft break stays inside its paragraph.
    private func inline(_ source: String, font: NSFont, color: NSColor) -> NSAttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return NSAttributedString(string: Self.softBreaks(source), attributes: plain)
        }
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes = plain
            var runFont = font
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                runFont = style.inlineCode
                attributes[.backgroundColor] = style.inlineCodeFill
            }
            if intent.contains(.stronglyEmphasized) {
                runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask)
            }
            if intent.contains(.emphasized) {
                runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link { attributes[.link] = link }
            attributes[.font] = runFont
            let characters = Self.softBreaks(String(parsed[run.range].characters))
            result.append(NSAttributedString(string: characters, attributes: attributes))
        }
        return result
    }

    /// A line separator breaks the line without starting a paragraph, so no gap opens above it.
    private static func softBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "\u{2028}")
    }

    private func monospacedDigits(_ font: NSFont) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
    }
}

/// A block drawn as the rounded card code and tables sat on as SwiftUI views.
class MarkdownCardBlock: NSTextBlock {
    private let fill: NSColor
    private let stroke: NSColor
    private let radius: CGFloat

    init(fill: NSColor, stroke: NSColor, radius: CGFloat) {
        self.fill = fill
        self.stroke = stroke
        self.radius = radius
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The card itself: the frame AppKit passes still holds the block's margins.
    func cardRect(in frame: NSRect) -> NSRect {
        let left = width(for: .margin, edge: .minX)
        let top = width(for: .margin, edge: .minY)
        return NSRect(
            x: frame.minX + left, y: frame.minY + top,
            width: frame.width - left - width(for: .margin, edge: .maxX),
            height: frame.height - top - width(for: .margin, edge: .maxY))
    }

    override func drawBackground(
        withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        let card = cardRect(in: frameRect).insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.stroke()
    }
}

/// A code card; the language label is drawn, not typed, so a copy never picks it up.
final class MarkdownCodeBlock: MarkdownCardBlock {
    let source: String
    private let language: String?
    private let label: NSFont
    private let labelColor: NSColor

    init(
        source: String, language: String?, label: NSFont, labelColor: NSColor, fill: NSColor,
        stroke: NSColor, radius: CGFloat
    ) {
        self.source = source
        self.language = language
        self.label = label
        self.labelColor = labelColor
        super.init(fill: fill, stroke: stroke, radius: radius)
    }

    override func drawBackground(
        withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        super.drawBackground(
            withFrame: frameRect, in: controlView, characterRange: charRange, layoutManager: layoutManager)
        guard let language, !language.isEmpty else { return }
        let card = cardRect(in: frameRect)
        let origin = NSPoint(
            x: card.minX + width(for: .padding, edge: .minX),
            y: card.minY + width(for: .padding, edge: .maxY))
        (language as NSString).draw(at: origin, withAttributes: [.font: label, .foregroundColor: labelColor])
    }
}

/// A table on the same card as a code block.
final class MarkdownTableBlock: NSTextTable {
    private let fill: NSColor
    private let stroke: NSColor
    private let radius: CGFloat

    init(fill: NSColor, stroke: NSColor, radius: CGFloat) {
        self.fill = fill
        self.stroke = stroke
        self.radius = radius
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func drawBackground(
        withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        let left = width(for: .margin, edge: .minX)
        let top = width(for: .margin, edge: .minY)
        let card = NSRect(
            x: frameRect.minX + left, y: frameRect.minY + top,
            width: frameRect.width - left, height: frameRect.height - top
        ).insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.stroke()
    }
}

/// A blockquote's leading bar; the text inside is inset past it by the block's padding.
final class MarkdownQuoteBlock: NSTextBlock {
    private let color: NSColor
    private let barWidth: CGFloat

    init(color: NSColor, width: CGFloat) {
        self.color = color
        self.barWidth = width
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func drawBackground(
        withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        let left = width(for: .margin, edge: .minX)
        let top = width(for: .margin, edge: .minY)
        let bar = NSRect(
            x: frameRect.minX + left, y: frameRect.minY + top, width: barWidth,
            height: frameRect.height - top)
        color.setFill()
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }
}

/// A horizontal rule, drawn through the middle of its one short, empty line.
final class MarkdownRuleBlock: NSTextBlock {
    private let color: NSColor
    private let thickness: CGFloat

    init(color: NSColor, thickness: CGFloat) {
        self.color = color
        self.thickness = thickness
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func drawBackground(
        withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        let left = width(for: .margin, edge: .minX)
        let top = width(for: .margin, edge: .minY)
        let line = NSRect(
            x: frameRect.minX + left, y: frameRect.minY + top + (frameRect.height - top - thickness) / 2,
            width: frameRect.width - left, height: thickness)
        color.setFill()
        line.fill()
    }
}
