import Foundation

/// Every string the stock widgets show, so tiles and popovers never format a number themselves.
enum StockFormat {
    static let placeholder = "—"

    /// ISO 4217 currencies with no minor unit, which a bare price shows without decimals.
    private static let wholeUnitCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV",
        "XAF", "XOF", "XPF",
    ]
    private static let maximumFractionDigits = 8
    /// Below this a price needs significant digits, not decimals, to say anything at all.
    private static let tinyPrice = 0.01

    /// A percent at the two decimals it is shown with, and never a negative zero.
    static func roundedPercent(_ percent: Double) -> Double {
        let rounded = (percent * 100).rounded() / 100
        return rounded == 0 ? 0 : rounded
    }

    /// `+1.23%`, `-0.40%`, and a bare `0.00%` for a move too small to show.
    static func percent(_ percent: Double?, locale: Locale = .current) -> String {
        guard let percent, percent.isFinite else { return placeholder }
        return (roundedPercent(percent) / 100).formatted(
            .percent.locale(locale).precision(.fractionLength(2))
                .sign(strategy: .always(includingZero: false)))
    }

    private static func magnitude(ofPercent percent: Double, locale: Locale) -> String {
        (abs(roundedPercent(percent)) / 100).formatted(
            .percent.locale(locale).precision(.fractionLength(2)))
    }

    /// A price in its currency. `fractionDigits` is Yahoo's own `priceHint` for the instrument.
    static func price(
        _ value: Double?, currency: String, fractionDigits: Int? = nil, locale: Locale = .current
    ) -> String {
        guard let value, value.isFinite else { return placeholder }
        let precision = precision(for: value, currency: currency, hint: fractionDigits)
        return amount(value, currency: currency, precision: precision, signed: false, locale: locale)
    }

    /// A move with its sign, in the decimals of the `price` it moved, so a cent is never `+$0.003`.
    static func change(
        _ value: Double?, price: Double, currency: String, fractionDigits: Int? = nil,
        locale: Locale = .current
    ) -> String {
        guard let value, value.isFinite, price.isFinite else { return placeholder }
        let precision = precision(for: price, currency: currency, hint: fractionDigits)
        return amount(value, currency: currency, precision: precision, signed: true, locale: locale)
    }

    /// `3.91M`: a day's volume is only ever read as an order of magnitude.
    static func volume(_ value: Double?, locale: Locale = .current) -> String {
        guard let value, value.isFinite else { return placeholder }
        return value.formatted(
            .number.locale(locale).notation(.compactName).precision(.significantDigits(1...3)))
    }

    /// A bar's time as its range reads it: a clock for a day, a weekday for a week, a date beyond.
    static func pointTime(
        _ date: Date, range: StockRange, timeZone: TimeZone, locale: Locale = .current
    ) -> String {
        let base = Date.FormatStyle(
            locale: locale, calendar: Calendar(identifier: .gregorian), timeZone: timeZone)
        switch range {
        case .day: return date.formatted(base.hour().minute())
        case .fiveDays: return date.formatted(base.weekday(.abbreviated).hour().minute())
        case .month, .sixMonths: return date.formatted(base.month(.abbreviated).day())
        case .year: return date.formatted(base.month(.abbreviated).day().year())
        }
    }

    /// The chart's two end labels: the session's bells for a day, the first and last bar otherwise.
    static func axisLabels(
        for series: StockSeries, range: StockRange, timeZone: TimeZone, locale: Locale = .current
    ) -> (leading: String, trailing: String)? {
        let ends: (Date, Date)?
        if let axis = series.axis {
            ends = (axis.start, axis.end)
        } else if let first = series.points.first, let last = series.points.last {
            ends = (first.time, last.time)
        } else {
            ends = nil
        }
        guard let (start, end) = ends else { return nil }
        return (
            pointTime(start, range: range, timeZone: timeZone, locale: locale),
            pointTime(end, range: range, timeZone: timeZone, locale: locale)
        )
    }

    /// What VoiceOver reads for a tile: the name, the price, and which way it moved.
    static func spoken(_ quote: StockQuote, locale: Locale = .current) -> String {
        var parts = [quote.name, price(quote.price, currency: quote.currency, locale: locale)]
        if let percent = quote.percentChange, percent.isFinite {
            parts.append("\(quote.direction.spoken) \(magnitude(ofPercent: percent, locale: locale))")
        }
        parts.append(quote.marketState.title)
        return parts.joined(separator: ", ")
    }

    private static func precision(
        for value: Double, currency: String, hint: Int?
    ) -> NumberFormatStyleConfiguration.Precision {
        if value != 0, abs(value) < tinyPrice { return .significantDigits(2...4) }
        if let hint {
            let digits = min(max(hint, 0), maximumFractionDigits)
            return .fractionLength(digits...digits)
        }
        if value == 0 || abs(value) >= 1 {
            return .fractionLength((wholeUnitCurrencies.contains(currency) ? 0 : 2)...2)
        }
        return .significantDigits(2...4)
    }

    /// A code outside ISO 4217, such as Yahoo's pence `GBp`, trails the number instead.
    private static func amount(
        _ value: Double, currency: String, precision: NumberFormatStyleConfiguration.Precision,
        signed: Bool, locale: Locale
    ) -> String {
        if Locale.commonISOCurrencyCodes.contains(currency) {
            let style = FloatingPointFormatStyle<Double>.Currency(code: currency, locale: locale)
                .presentation(.narrow).precision(precision)
            return value.formatted(signed ? style.sign(strategy: .always(showZero: false)) : style)
        }
        let style = FloatingPointFormatStyle<Double>(locale: locale).precision(precision)
        let number = value.formatted(
            signed ? style.sign(strategy: .always(includingZero: false)) : style)
        return currency.isEmpty ? number : "\(number) \(currency)"
    }
}
