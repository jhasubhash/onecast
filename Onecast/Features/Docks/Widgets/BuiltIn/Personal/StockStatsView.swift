import SwiftUI

/// A quote's figures as a grid of captioned values; whatever Yahoo left out is left out here.
struct StockStatsView: View {
    let quote: StockQuote

    private let locale = Locale.autoupdatingCurrent

    private struct Stat: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
            alignment: .leading, spacing: Theme.Spacing.md
        ) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(stat.title)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(stat.value)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var stats: [Stat] {
        let prices: [(String, Double?)] = [
            ("Open", quote.open), ("Day high", quote.dayHigh), ("Day low", quote.dayLow),
            ("Prev close", quote.previousClose), ("52-wk high", quote.yearHigh),
            ("52-wk low", quote.yearLow),
        ]
        let shown = prices.compactMap { title, value in
            value.map { Stat(title: title, value: quote.formatted($0, locale: locale)) }
        }
        let volume = quote.volume.map { [Stat(title: "Volume", value: StockFormat.volume($0, locale: locale))] }
        return shown + (volume ?? [])
    }
}
