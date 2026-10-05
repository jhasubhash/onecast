import Foundation

/// A chart's closes, oldest first, with Yahoo's null bars already dropped.
struct StockSeries: Sendable, Equatable {
    struct Point: Sendable, Equatable {
        let time: Date
        let close: Double
    }

    let points: [Point]
    /// The trading session a one-day chart's x-axis spans; nil for every other range.
    let axis: StockTradingWindow?

    /// First close to last, for the caption that says how the range went.
    var rangeChange: (amount: Double, percent: Double?)? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        let amount = last.close - first.close
        return (amount, first.close != 0 ? amount / first.close * 100 : nil)
    }
}
