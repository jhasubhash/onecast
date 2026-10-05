import Foundation

/// Which of a watchlist's symbols the compact tile shows, from the wall clock alone.
enum StockRotation {
    static let period: TimeInterval = 5

    /// Every tile steps on the same beat, and a restarted view picks up where the clock is.
    static func index(at date: Date, count: Int, period: TimeInterval = period) -> Int {
        guard count > 0, period > 0 else { return 0 }
        let step = Int((date.timeIntervalSinceReferenceDate / period).rounded(.down))
        return ((step % count) + count) % count
    }
}
