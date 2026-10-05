import Foundation

/// How soon a stock tile asks Yahoo again: briskly while a market trades, lazily otherwise.
enum StockCadence {
    static let open: TimeInterval = 60
    static let closed: TimeInterval = 15 * 60

    /// Open when any of the quotes is in its regular session; a watchlist spans many exchanges.
    static func interval(for states: [StockMarketState]) -> TimeInterval {
        states.contains(where: \.isOpen) ? open : closed
    }

    /// After a failure: soon when asking again can help, at the lazy pace when it cannot.
    static func interval(after error: StockError) -> TimeInterval {
        error.isTransient ? open : closed
    }

    /// Seconds until the next fetch is due; 0 when it is already overdue or nothing was fetched.
    static func delay(nextFetch: Date?, now: Date) -> TimeInterval {
        guard let nextFetch else { return 0 }
        return max(0, nextFetch.timeIntervalSince(now))
    }
}
