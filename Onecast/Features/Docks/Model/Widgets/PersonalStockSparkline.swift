import Foundation

/// A series reduced to what a renderer needs: points in a unit square, whatever the price scale.
struct StockSparkline: Sendable, Equatable {
    struct Point: Sendable, Equatable {
        /// 0 at the left edge, 1 at the right.
        let x: Double
        /// 0 at the lowest close, 1 at the highest.
        let y: Double
        let value: Double
        let time: Date
    }

    let points: [Point]
    /// Where the previous close sits on the same scale, so a day's chart can mark its reference.
    let baseline: Double?

    var isDrawable: Bool { points.count >= 2 }

    /// With an axis x is time in the session, so a morning fills the left; else bars spread evenly.
    init(series: StockSeries, baseline: Double? = nil) {
        let closes = series.points.map(\.close)
        var low = closes.min() ?? 0
        var high = closes.max() ?? 0
        if let baseline, !closes.isEmpty {
            low = min(low, baseline)
            high = max(high, baseline)
        }
        let span = high - low
        let last = max(series.points.count - 1, 1)
        func unit(_ value: Double) -> Double { span > 0 ? (value - low) / span : 0.5 }

        points = series.points.enumerated().map { index, point in
            Point(
                x: series.axis?.fraction(of: point.time) ?? Double(index) / Double(last),
                y: unit(point.close), value: point.close, time: point.time)
        }
        self.baseline = baseline.map(unit)
    }

    /// The point nearest a horizontal position, for a hover that snaps to real bars.
    func nearestIndex(toX x: Double) -> Int? {
        guard let first = points.first else { return nil }
        var best = (index: 0, distance: abs(first.x - x))
        for (index, point) in points.enumerated() where abs(point.x - x) < best.distance {
            best = (index, abs(point.x - x))
        }
        return best.index
    }
}
