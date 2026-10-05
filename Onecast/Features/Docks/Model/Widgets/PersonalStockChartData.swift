import Foundation

/// One chart fetch: the range asked for, its closes, and the quote read from the same answer.
struct StockChartData: Sendable, Equatable {
    let range: StockRange
    let quote: StockQuote
    let series: StockSeries
    let fetchedAt: Date

    /// The percent the chart as a whole moved: the day's change for one day, first to last beyond.
    var changePercent: Double? {
        range.spansTradingDay ? quote.percentChange : series.rangeChange?.percent
    }

    var trend: StockDirection { StockDirection(percent: changePercent) }

    /// The reference line a one-day chart marks, as yesterday's close.
    var baseline: Double? { range.spansTradingDay ? quote.previousClose : nil }
}
