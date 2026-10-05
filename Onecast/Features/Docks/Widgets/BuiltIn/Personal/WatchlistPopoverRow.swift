import SwiftUI

/// A watchlist row in the popover: the symbol and name, the price and move; the click selects it.
struct WatchlistPopoverRow: View {
    let entry: WatchlistModel.Entry
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false
    private let locale = Locale.autoupdatingCurrent
    static let height: CGFloat = 44
    private static let glyph: CGFloat = 9

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(entry.symbol)
                        .font(Theme.Typography.rowTitle.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .lineLimit(1)
                Spacer(minLength: Theme.Spacing.md)
                VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                    Text(entry.quote.map { $0.formatted($0.price, locale: locale) } ?? StockFormat.placeholder)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    movement
                }
                .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Self.height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(fill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String {
        entry.quote?.name ?? entry.failure?.message ?? StockFormat.placeholder
    }

    @ViewBuilder
    private var movement: some View {
        if let quote = entry.quote {
            StockChangeLabel(
                direction: quote.direction, text: quote.percentText(locale: locale),
                font: Theme.Typography.keyCap, glyphSize: Self.glyph)
        }
    }

    private var fill: Color {
        if isSelected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : .clear
    }

    private var label: String {
        guard let quote = entry.quote else { return "\(entry.symbol), \(subtitle)" }
        return "\(entry.symbol), " + StockFormat.spoken(quote, locale: locale)
    }
}
