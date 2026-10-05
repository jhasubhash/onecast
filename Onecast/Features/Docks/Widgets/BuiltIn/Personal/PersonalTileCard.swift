import SwiftUI

/// The inset and centring every Personal tile shares; the host draws the card and its corners.
struct PersonalTileCard<Content: View>: View {
    let metrics: PersonalTileMetrics
    let content: Content

    init(_ metrics: PersonalTileMetrics, @ViewBuilder content: () -> Content) {
        self.metrics = metrics
        self.content = content()
    }

    var body: some View {
        content
            .padding(metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A tile's top line: a small accent dot and a short secondary label that truncates.
struct PersonalTileHeader: View {
    let metrics: PersonalTileMetrics
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: metrics.spacing) {
            Circle().fill(tint).frame(width: metrics.dotSize, height: metrics.dotSize)
            Text(title)
                .font(metrics.font(.caption, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Where every Personal popover agrees: one width, one inset, so the five read as a family.
enum PersonalPopover {
    static let width: CGFloat = 320
    static let padding: CGFloat = Theme.Spacing.xl
    /// A history or forecast list scrolls past this height instead of growing the popover.
    static let listMaxHeight: CGFloat = 260
}
