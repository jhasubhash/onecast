import Foundation

/// A watchlist's quotes in the order asked, with why each missing symbol has none.
struct StockBatch: Sendable, Equatable {
    let quotes: [StockQuote]
    let failures: [String: StockError]
    let fetchedAt: Date
}
