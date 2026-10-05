import SwiftUI

/// A popover's top: the name and symbol, the price, how it moved, and where the market is.
struct StockQuoteHeaderView: View {
    let symbol: String?
    let quote: StockQuote?

    private let locale = Locale.autoupdatingCurrent
    private static let glyph: CGFloat = 10

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(quote?.name ?? symbol ?? StockFormat.placeholder)
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                if let quote {
                    marketState(quote.marketState)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(quote.map { $0.formatted($0.price, locale: locale) } ?? StockFormat.placeholder)
                    .font(Theme.Typography.calcResult)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                movement
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(quote.map { StockFormat.spoken($0, locale: locale) } ?? "No quote")
    }

    private var subtitle: String {
        guard let quote else { return symbol ?? "" }
        return [quote.symbol, quote.currency].joined(separator: " · ")
    }

    private func marketState(_ state: StockMarketState) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(state.isOpen ? Theme.Colors.success : Theme.Colors.textTertiary)
                .frame(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
            Text(state.title)
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private var movement: some View {
        if let quote {
            StockChangeLabel(
                direction: quote.direction,
                text: "\(quote.changeText(locale: locale)) (\(quote.percentText(locale: locale)))",
                font: Theme.Typography.rowTrailing, glyphSize: Self.glyph)
        }
    }
}
