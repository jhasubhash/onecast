import SwiftUI

/// One symbol on a Watchlist tile: a single line when the cell is wide, a stack when it is not.
struct WatchlistTileCell: View {
    let entry: WatchlistModel.Entry
    let metrics: PersonalTileMetrics

    private let locale = Locale.autoupdatingCurrent
    /// A cell this much wider than it is tall has the room to read as a line.
    private static let lineAspect: CGFloat = 1.6

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= proxy.size.height * Self.lineAspect {
                    line
                } else {
                    stack
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var line: some View {
        HStack(spacing: metrics.spacing) {
            header
            Spacer(minLength: 0)
            price(.label)
            change
        }
    }

    private var stack: some View {
        VStack(spacing: metrics.spacing / 2) {
            header
            price(.value)
            change
        }
    }

    private var header: some View {
        PersonalTileHeader(
            metrics: metrics, title: entry.symbol,
            tint: entry.quote?.direction.tint ?? Theme.Colors.textTertiary)
    }

    private func price(_ role: PersonalTileMetrics.Role) -> some View {
        Text(entry.quote.map { $0.formatted($0.price, locale: locale) } ?? StockFormat.placeholder)
            .font(metrics.font(role, weight: .bold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private var change: some View {
        if let quote = entry.quote {
            StockChangeLabel(
                direction: quote.direction, text: quote.percentText(locale: locale),
                font: metrics.font(.caption), glyphSize: metrics.symbolSize(0.1))
        } else {
            Text(StockFormat.placeholder)
                .font(metrics.font(.caption))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}
