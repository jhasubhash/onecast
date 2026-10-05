import Foundation

/// One instrument's day: price, how it moved, and the figures a stats row shows.
struct StockQuote: Sendable, Equatable, Identifiable {
    let symbol: String
    let name: String
    let currency: String
    let price: Double
    let change: Double?
    let percentChange: Double?
    let previousClose: Double?
    let open: Double?
    let dayHigh: Double?
    let dayLow: Double?
    let yearHigh: Double?
    let yearLow: Double?
    let volume: Double?
    let marketState: StockMarketState
    let timeZoneIdentifier: String?
    /// Yahoo's `priceHint`: how many decimals this instrument is quoted to.
    let fractionDigits: Int?

    var id: String { symbol }
    var direction: StockDirection { StockDirection(percent: percentChange) }

    /// The exchange's own clock, so a bar reads as its traders saw it.
    var timeZone: TimeZone { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current }

    /// Any figure of this quote's, in its own currency and decimals.
    func formatted(_ figure: Double?, locale: Locale = .current) -> String {
        StockFormat.price(figure, currency: currency, fractionDigits: fractionDigits, locale: locale)
    }

    func changeText(locale: Locale = .current) -> String {
        StockFormat.change(
            change, price: price, currency: currency, fractionDigits: fractionDigits, locale: locale)
    }

    func percentText(locale: Locale = .current) -> String {
        StockFormat.percent(percentChange, locale: locale)
    }
}
