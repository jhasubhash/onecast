import SwiftUI

/// The popover's chart: a range switch, the chart for it with a hover readout, and the stats.
struct StockChartSectionView: View {
    let chart: StockChartModel
    let symbol: String?
    /// The day's quote, which the stats read; a longer range's own meta has no day figures.
    let quote: StockQuote?

    private let locale = Locale.autoupdatingCurrent
    private static let chartHeight: CGFloat = 120
    private static let loadingOpacity = 0.4

    var body: some View {
        @Bindable var chart = chart
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            StockRangePicker(selection: $chart.range)
            plot
            if let data = chart.data, data.series.points.count >= 2 {
                caption(data)
            }
            if let quote {
                StockStatsView(quote: quote)
            }
        }
        .task(id: chart.request(symbol: symbol)) {
            guard let symbol else { return }
            await chart.run(symbol: symbol, range: chart.range)
        }
    }

    @ViewBuilder
    private var plot: some View {
        Group {
            if let data = chart.data, data.series.points.count >= 2 {
                StockSparklineView(
                    sparkline: StockSparkline(series: data.series, baseline: data.baseline),
                    tint: data.trend.tint, style: .chart,
                    readout: { readout($0, in: data) }
                )
                .opacity(isCurrent(data) ? 1 : Self.loadingOpacity)
                .accessibilityLabel("\(data.range.title) price chart")
                .accessibilityValue(StockFormat.percent(data.changePercent, locale: locale))
            } else if chart.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(chart.error == nil ? "No chart data for this range." : "No chart")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.chartHeight)
    }

    /// The chart on show is for the range picked; until then the old one waits, dimmed.
    private func isCurrent(_ data: StockChartData) -> Bool {
        data.range == chart.range && data.quote.symbol == symbol
    }

    private func caption(_ data: StockChartData) -> some View {
        let labels = StockFormat.axisLabels(
            for: data.series, range: data.range, timeZone: data.quote.timeZone, locale: locale)
        return HStack {
            Text(labels?.leading ?? "")
            Spacer(minLength: Theme.Spacing.md)
            StockChangeLabel(
                direction: data.trend, text: StockFormat.percent(data.changePercent, locale: locale),
                font: Theme.Typography.keyCap, glyphSize: Self.captionGlyph)
            Spacer(minLength: Theme.Spacing.md)
            Text(labels?.trailing ?? "")
        }
        .font(Theme.Typography.keyCap)
        .foregroundStyle(Theme.Colors.textTertiary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private static let captionGlyph: CGFloat = 8

    private func readout(_ point: StockSparkline.Point, in data: StockChartData) -> String {
        let price = data.quote.formatted(point.value, locale: locale)
        let time = StockFormat.pointTime(
            point.time, range: data.range, timeZone: data.quote.timeZone, locale: locale)
        return "\(price)  ·  \(time)"
    }
}
