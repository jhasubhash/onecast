import Foundation

/// A span of exchange time, such as one regular session.
struct StockTradingWindow: Sendable, Equatable {
    let start: Date
    let end: Date

    /// Start-inclusive, end-exclusive: at the closing bell the session is already over.
    func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// The last tick of a session carries the closing time, so a chart axis must admit it.
    func spans(_ date: Date) -> Bool { date >= start && date <= end }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Where `date` falls in the window, 0 at the open and 1 at the close, clamped.
    func fraction(of date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / duration, 0), 1)
    }
}
