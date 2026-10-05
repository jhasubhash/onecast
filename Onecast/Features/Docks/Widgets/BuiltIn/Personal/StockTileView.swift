import OnecastPluginKit
import SwiftUI

/// The Stock tile: symbol, bold price, move and today's chart, centred like the Personal tiles.
struct StockTileView: View {
    let model: StockModel
    let context: DockWidgetContext

    private let locale = Locale.autoupdatingCurrent
    /// Below this a tile is too small for even a faint chart to read as anything but noise.
    private static let backdropMinimumLength: CGFloat = 44
    private static let backdropOpacity = 0.35
    private static let staleOpacity = 0.5
    /// The share of a horizontal tile's width the text column takes; the chart gets the rest.
    private static func textShare(_ metrics: PersonalTileMetrics) -> CGFloat {
        metrics.size == .expanded ? 0.3 : 0.46
    }

    var body: some View {
        let metrics = PersonalTileMetrics(context)
        PersonalTileCard(metrics) {
            if metrics.isCompact {
                compact(metrics)
            } else {
                strip(metrics)
            }
        }
        .opacity(model.isStale ? Self.staleOpacity : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .task(id: context.instanceID) { await model.run(preferences: context.preferences) }
    }

    private func compact(_ metrics: PersonalTileMetrics) -> some View {
        ZStack {
            if metrics.tileLength >= Self.backdropMinimumLength {
                backdrop
                    .opacity(Self.backdropOpacity)
                    .padding(-metrics.padding / 2)
            }
            readout(metrics, price: .value)
        }
    }

    private func strip(_ metrics: PersonalTileMetrics) -> some View {
        GeometryReader { proxy in
            let layout =
                metrics.isVertical
                ? AnyLayout(VStackLayout(spacing: metrics.spacing))
                : AnyLayout(HStackLayout(spacing: metrics.spacing * 2))
            layout {
                readout(metrics, price: metrics.size == .expanded && !metrics.isVertical ? .display : .value)
                    .frame(width: metrics.isVertical ? nil : proxy.size.width * Self.textShare(metrics))
                VStack(spacing: metrics.spacing / 2) {
                    dayChart
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    nameCaption(metrics)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The header, the bold price and the move: the three lines every size shows.
    private func readout(
        _ metrics: PersonalTileMetrics, price role: PersonalTileMetrics.Role
    ) -> some View {
        VStack(spacing: metrics.spacing / 2) {
            PersonalTileHeader(
                metrics: metrics, title: model.symbol ?? StockFormat.placeholder,
                tint: model.quote?.direction.tint ?? Theme.Colors.textTertiary)
            Text(model.quote.map { $0.formatted($0.price, locale: locale) } ?? StockFormat.placeholder)
                .font(metrics.font(role, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            change(metrics)
        }
    }

    @ViewBuilder
    private func change(_ metrics: PersonalTileMetrics) -> some View {
        if let quote = model.quote {
            StockChangeLabel(
                direction: quote.direction, text: quote.percentText(locale: locale),
                font: metrics.font(.caption), glyphSize: metrics.symbolSize(0.1))
        } else {
            Text(StockFormat.placeholder)
                .font(metrics.font(.caption))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private func nameCaption(_ metrics: PersonalTileMetrics) -> some View {
        if let name = model.quote?.name {
            Text(name)
                .font(metrics.font(.caption, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// The day so far, spread across the tile: a trend to glance at, not a place on the day's axis.
    @ViewBuilder
    private var backdrop: some View {
        if let data = model.chart {
            StockSparklineView(
                sparkline: StockSparkline(series: StockSeries(points: data.series.points, axis: nil)),
                tint: data.trend.tint, style: .backdrop)
        }
    }

    /// The day on its own axis: the bars so far at the left, the hours to come left empty.
    @ViewBuilder
    private var dayChart: some View {
        if let data = model.chart {
            StockSparklineView(
                sparkline: StockSparkline(series: data.series, baseline: data.baseline),
                tint: data.trend.tint, style: .tile)
        }
    }

    private var summary: String {
        guard let quote = model.quote else {
            return "\(model.symbol ?? "Stock"), no quote. \(model.error?.message ?? "Loading.")"
        }
        let spoken = StockFormat.spoken(quote, locale: locale)
        return model.isStale ? "\(spoken), not up to date" : spoken
    }
}
