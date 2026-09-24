import AppKit
import SwiftUI

/// A reply's closing ```choices``` lines, as buttons that send their text as the next message.
struct ChatChoiceChips: View {
    @Environment(\.metrics) private var metrics
    let choices: [String]
    let choose: (String) -> Void

    var body: some View {
        ChatFlowLayout(spacing: metrics.spacing.sm) {
            ForEach(choices, id: \.self) { choice in
                Button { choose(choice) } label: {
                    Text(choice)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, metrics.spacing.lg)
                        .padding(.vertical, metrics.spacing.sm)
                        .background(Capsule().fill(Theme.Colors.controlSurface))
                        .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The pages a finished reply linked to, numbered in the order it cited them.
struct ChatSourceChips: View {
    @Environment(\.metrics) private var metrics
    let references: [ChatReference]

    var body: some View {
        ChatFlowLayout(spacing: metrics.spacing.sm) {
            ForEach(Array(references.enumerated()), id: \.element) { offset, reference in
                Button { NSWorkspace.shared.open(reference.url) } label: {
                    HStack(spacing: metrics.spacing.xs) {
                        Text("\(offset + 1)")
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(reference.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.horizontal, metrics.spacing.md)
                    .padding(.vertical, metrics.spacing.xs)
                    .frame(maxWidth: metrics.scaled(Self.maxChipWidth))
                    .background(Capsule().fill(Theme.Colors.cardFill))
                    .overlay(Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: Theme.Size.hairline))
                }
                .buttonStyle(.plain)
                .help(reference.url.absoluteString)
            }
        }
    }

    /// Past this a page title middle-truncates, so a long one never takes a whole row.
    private static let maxChipWidth: CGFloat = 220
}

/// Left-to-right wrapping, since SwiftUI has none; the chat's own, never another feature's.
struct ChatFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
