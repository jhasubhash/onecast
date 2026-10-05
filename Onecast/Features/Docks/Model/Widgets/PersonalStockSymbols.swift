import Foundation

/// Turns what the user typed into the tickers Yahoo is asked for.
enum StockSymbols {
    static let defaultSymbol = "AAPL"
    static let defaultWatchlist = "AAPL, MSFT, GOOGL, AMZN"
    static let watchlistLimit = 12
    /// Long enough for a Yahoo option symbol, short enough to keep a request line sane.
    private static let maximumLength = 24
    private static let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
    private static let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-^=&")
    private static let alphanumerics = CharacterSet.alphanumerics

    /// Uppercased, deduplicated tickers in typed order, up to `limit`; unusable tokens are dropped.
    static func parse(_ text: String?, limit: Int = watchlistLimit) -> [String] {
        guard let text, limit > 0 else { return [] }
        var seen = Set<String>()
        var symbols: [String] = []
        for token in text.components(separatedBy: separators) {
            guard let symbol = normalised(token), seen.insert(symbol).inserted else { continue }
            symbols.append(symbol)
            if symbols.count == limit { break }
        }
        return symbols
    }

    /// The one ticker a Stock tile shows: the first valid one typed.
    static func single(_ text: String?) -> String? {
        parse(text, limit: 1).first
    }

    /// `$aapl` is how traders write a cashtag; the `$` is not part of the ticker.
    private static func normalised(_ token: String) -> String? {
        let symbol = String(token.drop { $0 == "$" }).uppercased()
        guard !symbol.isEmpty, symbol.count <= maximumLength,
            symbol.unicodeScalars.allSatisfy(allowed.contains),
            symbol.unicodeScalars.contains(where: alphanumerics.contains)
        else { return nil }
        return symbol
    }
}
