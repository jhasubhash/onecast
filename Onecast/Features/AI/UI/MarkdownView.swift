import SwiftUI

/// Renders parsed markdown; the body is erased so a nested list cannot make `Body` circular.
struct MarkdownView: View {
    @Environment(\.metrics) private var metrics
    let blocks: [MarkdownBlock]
    var spacing: CGFloat?

    var body: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: spacing ?? metrics.spacing.lg) {
                ForEach(Array(MarkdownProse.runs(blocks).enumerated()), id: \.offset) { offset, run in
                    Group {
                        switch run {
                        case .prose(let prose): MarkdownProseView(blocks: prose)
                        case .block(let block): MarkdownBlockView(block: block)
                        }
                    }
                    .padding(.top, offset > 0 && run.opensWithHeading ? metrics.spacing.sm : 0)
                }
            })
    }
}

/// Prose drawn as one `Text`, because SwiftUI's selection never crosses from one `Text` into the next.
private struct MarkdownProseView: View {
    @Environment(\.metrics) private var metrics
    let blocks: [MarkdownBlock]

    var body: some View {
        Text(MarkdownProse.attributed(blocks, metrics))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Joins headings, paragraphs and lists into one string; code, tables, quotes and rules stay views.
private enum MarkdownProse {
    enum Run {
        case prose([MarkdownBlock])
        case block(MarkdownBlock)

        var opensWithHeading: Bool {
            switch self {
            case .prose(let blocks): blocks.first?.isHeading ?? false
            case .block(let block): block.isHeading
            }
        }
    }

    static func runs(_ blocks: [MarkdownBlock]) -> [Run] {
        var runs: [Run] = []
        var prose: [MarkdownBlock] = []
        for block in blocks {
            if joins(block) {
                prose.append(block)
                continue
            }
            if !prose.isEmpty { runs.append(.prose(prose)) }
            prose = []
            runs.append(.block(block))
        }
        if !prose.isEmpty { runs.append(.prose(prose)) }
        return runs
    }

    /// A list joins only when every item does, so one fenced block keeps the whole list as views.
    private static func joins(_ block: MarkdownBlock) -> Bool {
        switch block {
        case .heading, .paragraph: true
        case .bulletList(let items), .numberedList(_, let items):
            items.allSatisfy { $0.blocks.allSatisfy(joins) }
        case .code, .quote, .table, .rule: false
        }
    }

    static func attributed(_ blocks: [MarkdownBlock], _ metrics: InterfaceMetrics) -> AttributedString {
        var text = AttributedString()
        for (offset, block) in blocks.enumerated() {
            if offset > 0 {
                text += AttributedString("\n")
                let heading = block.isHeading ? metrics.spacing.sm : 0
                text += gap(metrics.spacing.lg + heading)
            }
            append(block, indent: "", to: &text, metrics)
        }
        return text
    }

    private static func append(
        _ block: MarkdownBlock, indent: String, to text: inout AttributedString,
        _ metrics: InterfaceMetrics
    ) {
        switch block {
        case .heading(let level, let source):
            var heading = MarkdownInline.attributed(source, metrics)
            let font = MarkdownInline.headingFont(level, metrics)
            // Inline code keeps its own face; only the plain runs take the heading's.
            for range in heading.runs.filter({ $0.font == nil }).map(\.range) {
                heading[range].font = font
            }
            text += heading
        case .paragraph(let source):
            text += MarkdownInline.attributed(source, metrics)
        case .bulletList(let items):
            appendList(items, start: nil, indent: indent, to: &text, metrics)
        case .numberedList(let start, let items):
            appendList(items, start: start, indent: indent, to: &text, metrics)
        case .code, .quote, .table, .rule:
            break
        }
    }

    /// Markers are real text, so a copied list keeps its bullets and numbers.
    private static func appendList(
        _ items: [MarkdownBlock.Item], start: Int?, indent: String, to text: inout AttributedString,
        _ metrics: InterfaceMetrics
    ) {
        let nested = indent + "    "
        // No spacer lines inside a list: every line break in the `Text` is a line break in a copy.
        for (offset, item) in items.enumerated() {
            if offset > 0 { text += AttributedString("\n") }
            text += marker(for: item, at: offset, start: start, count: items.count, indent: indent)
            for (index, inner) in item.blocks.enumerated() {
                if index > 0 {
                    text += AttributedString("\n")
                    // A nested list indents its own markers; a later paragraph lines up under the text.
                    if !inner.isList { text += AttributedString(nested) }
                }
                append(inner, indent: nested, to: &text, metrics)
            }
        }
    }

    private static func marker(
        for item: MarkdownBlock.Item, at offset: Int, start: Int?, count: Int, indent: String
    ) -> AttributedString {
        let glyph: String
        var color = Theme.Colors.textSecondary
        if let checked = item.checked {
            glyph = checked ? "☑" : "☐"
            color = checked ? Theme.Colors.success : Theme.Colors.textTertiary
        } else if let start {
            // Figure spaces pad to the widest number, so the periods line up down the list.
            let widest = String(start + max(count - 1, 0)).count
            let number = String(start + offset)
            glyph = String(repeating: "\u{2007}", count: max(0, widest - number.count)) + number + "."
        } else {
            glyph = "•"
        }
        var marker = AttributedString(indent + glyph + "  ")
        marker.foregroundColor = color
        return marker
    }

    /// An empty line set small enough to add only `height`, the gap the stacked views had.
    private static func gap(_ height: CGFloat) -> AttributedString {
        var line = AttributedString("\n")
        line.font = .system(size: max(1, height / 1.2))
        return line
    }
}

extension MarkdownBlock {
    /// A heading opens a section, so it takes more air above it than two paragraphs need.
    fileprivate var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }

    fileprivate var isList: Bool {
        switch self {
        case .bulletList, .numberedList: true
        default: false
        }
    }
}

private struct MarkdownBlockView: View {
    @Environment(\.metrics) private var metrics
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading, .paragraph:
            MarkdownProseView(blocks: [block])
        // A list lands here only when an item holds a code block, table or quote.
        case .bulletList(let items):
            MarkdownListView(items: items, start: nil)
        case .numberedList(let start, let items):
            MarkdownListView(items: items, start: start)
        case .code(let language, let text):
            MarkdownCodeView(language: language, text: text)
        case .quote(let blocks):
            MarkdownQuoteView(blocks: blocks)
        case .table(let table):
            MarkdownTableView(table: table)
        case .rule:
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: Theme.Size.hairline)
        }
    }
}

private struct MarkdownListView: View {

    @Environment(\.metrics) private var metrics
    let items: [MarkdownBlock.Item]
    /// Nil for a bulleted list; otherwise the number the first item counts from.
    let start: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                    marker(at: offset, checked: item.checked)
                        .frame(minWidth: metrics.size.markdownListMarker, alignment: .trailing)
                    MarkdownView(blocks: item.blocks, spacing: metrics.spacing.xs)
                }
            }
        }
    }

    @ViewBuilder private func marker(at offset: Int, checked: Bool?) -> some View {
        if let checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Theme.Colors.success : Theme.Colors.textTertiary)
        } else if start != nil {
            // Padding to the list's widest number keeps a marker from wrapping mid-number.
            Text(orderedMarker(at: offset))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Text("•").foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// Right-aligned within the list by padding, since monospaced digits all measure the same.
    private func orderedMarker(at offset: Int) -> String {
        guard let start else { return "" }
        let widest = String(start + max(items.count - 1, 0)).count
        let number = String(start + offset)
        return String(repeating: " ", count: max(0, widest - number.count)) + number + "."
    }
}

private struct MarkdownQuoteView: View {

    @Environment(\.metrics) private var metrics
    let blocks: [MarkdownBlock]

    var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.lg) {
            RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
                .fill(Theme.Colors.border)
                .frame(width: metrics.size.markdownQuoteBar)
            MarkdownView(blocks: blocks)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
