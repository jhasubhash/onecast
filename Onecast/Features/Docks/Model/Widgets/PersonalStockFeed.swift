import Foundation

/// Reads Yahoo's JSON into the stock widgets' values. Pure: the clock is a parameter.
enum StockFeed {
    /// A chart answer for `symbol`: the quote in its meta and the closes it plotted.
    static func chart(
        from data: Data, symbol: String, range: StockRange, now: Date
    ) throws(StockError) -> StockChartData {
        let envelope = try decode(StockWire.ChartEnvelope.self, from: data)
        guard let body = envelope.chart else { throw .malformed }
        if let failure = body.error { throw error(for: failure, symbol: symbol) }
        guard let result = body.result?.first, let price = result.meta.regularMarketPrice else {
            throw .unknownSymbol(symbol)
        }
        let meta = result.meta
        let regular = window(meta.currentTradingPeriod?.value?.regular)
        let state = StockMarketState(
            at: now, pre: window(meta.currentTradingPeriod?.value?.pre), regular: regular,
            post: window(meta.currentTradingPeriod?.value?.post))
        let points = points(of: result)
        let sessions = meta.tradingPeriods?.value ?? []
        let axis = range.spansTradingDay
            ? tradingDay(of: points, sessions: sessions, fallback: regular) : nil

        let previous = meta.previousClose ?? (range.spansTradingDay ? meta.chartPreviousClose : nil)
        let moved = movement(
            price: price, previousClose: previous,
            reported: (meta.fulldayPrice, meta.fulldayChange, meta.fulldayChangePercent))
        let quote = StockQuote(
            symbol: symbol, name: meta.longName ?? meta.shortName ?? symbol,
            currency: meta.currency ?? "USD", price: price, change: moved.change,
            percentChange: moved.percent, previousClose: previous,
            open: range.spansTradingDay ? firstOpen(of: result) : nil,
            dayHigh: meta.regularMarketDayHigh, dayLow: meta.regularMarketDayLow,
            yearHigh: meta.fiftyTwoWeekHigh, yearLow: meta.fiftyTwoWeekLow,
            volume: meta.regularMarketVolume, marketState: state,
            timeZoneIdentifier: meta.exchangeTimezoneName, fractionDigits: digits(meta.priceHint))
        return StockChartData(
            range: range, quote: quote, series: StockSeries(points: points, axis: axis),
            fetchedAt: now)
    }

    /// A batched quote answer: one quote per requested symbol Yahoo knew, in the order asked.
    static func batch(from data: Data, symbols: [String], now: Date) throws(StockError) -> StockBatch {
        let envelope = try decode(StockWire.QuoteEnvelope.self, from: data)
        if let failure = failure(in: data) { throw error(for: failure, symbol: nil) }
        guard let rows = envelope.quoteResponse?.result else { throw .malformed }
        let found = rows.compactMap { $0.value.flatMap { quote(from: $0, now: now) } }
        var quotes: [StockQuote] = []
        var failures: [String: StockError] = [:]
        for symbol in symbols {
            if let quote = found.first(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }) {
                quotes.append(quote)
            } else {
                failures[symbol] = .unknownSymbol(symbol)
            }
        }
        return StockBatch(quotes: quotes, failures: failures, fetchedAt: now)
    }

    /// What an unsuccessful HTTP answer means. Yahoo explains itself in the body of most of them.
    static func error(status: Int, body: Data, symbol: String?) -> StockError {
        switch status {
        case 429: return .rateLimited
        case 401, 403: return .unauthorized
        case 500...599: return .server(status)
        default:
            if let failure = failure(in: body) { return error(for: failure, symbol: symbol) }
            return status == 404 ? symbol.map(StockError.unknownSymbol) ?? .server(status) : .server(status)
        }
    }

    private static func failure(in data: Data) -> StockWire.Failure? {
        (try? JSONDecoder().decode(StockWire.ErrorEnvelope.self, from: data))?.failure
    }

    private static func error(for failure: StockWire.Failure, symbol: String?) -> StockError {
        switch failure.code {
        case "Not Found"?:
            if let symbol { return .unknownSymbol(symbol) }
        case "Unauthorized"?:
            return .unauthorized
        default:
            break
        }
        return .api(failure.description ?? failure.code ?? StockError.malformed.message)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type, from data: Data
    ) throws(StockError) -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .malformed
        }
    }

    private static func quote(from row: StockWire.QuoteRow, now: Date) -> StockQuote? {
        guard let symbol = row.symbol, let price = row.regularMarketPrice else { return nil }
        let reported = (row.regularMarketChange, row.regularMarketChangePercent)
        let moved = movement(
            price: price, previousClose: row.regularMarketPreviousClose,
            reported: (price, reported.0, reported.1))
        return StockQuote(
            symbol: symbol, name: row.longName ?? row.shortName ?? symbol,
            currency: row.currency ?? "USD", price: price, change: moved.change,
            percentChange: moved.percent, previousClose: row.regularMarketPreviousClose,
            open: row.regularMarketOpen, dayHigh: row.regularMarketDayHigh,
            dayLow: row.regularMarketDayLow, yearHigh: row.fiftyTwoWeekHigh,
            yearLow: row.fiftyTwoWeekLow, volume: row.regularMarketVolume,
            marketState: StockMarketState(yahoo: row.marketState),
            timeZoneIdentifier: row.exchangeTimezoneName, fractionDigits: digits(row.priceHint))
    }

    /// Yahoo's own change when it matches the price shown: crypto's is 24-hour, not from the close.
    private static func movement(
        price: Double, previousClose: Double?,
        reported: (price: Double?, change: Double?, percent: Double?)
    ) -> (change: Double?, percent: Double?) {
        if let reportedPrice = reported.price, abs(reportedPrice - price) < 1e-9,
            let change = reported.change, let percent = reported.percent,
            change.isFinite, percent.isFinite
        {
            return (change, percent)
        }
        guard let previousClose, previousClose != 0 else { return (nil, nil) }
        let change = price - previousClose
        return (change, change / previousClose * 100)
    }

    /// Bars with a close, oldest first. Yahoo nulls a bar's close when nothing traded in it.
    private static func points(of result: StockWire.ChartResult) -> [StockSeries.Point] {
        let closes = result.indicators?.quote?.first?.close ?? []
        return zip(result.timestamp ?? [], closes).compactMap { time, close in
            guard let time, let close, time.isFinite, close.isFinite else { return nil }
            return StockSeries.Point(time: Date(timeIntervalSince1970: time), close: close)
        }
    }

    private static func firstOpen(of result: StockWire.ChartResult) -> Double? {
        result.indicators?.quote?.first?.open?.lazy.compactMap { $0 }.first { $0.isFinite }
    }

    /// The session holding the first bar: the last trading day listed, else the current one.
    private static func tradingDay(
        of points: [StockSeries.Point], sessions: [[StockWire.Period]],
        fallback: StockTradingWindow?
    ) -> StockTradingWindow? {
        guard let first = points.first else { return nil }
        let lastDay = sessions.last.flatMap { periods -> StockTradingWindow? in
            let starts = periods.compactMap(\.start)
            let ends = periods.compactMap(\.end)
            guard let start = starts.min(), let end = ends.max() else { return nil }
            return window(StockWire.Period(start: start, end: end))
        }
        return [lastDay, fallback].lazy.compactMap { $0 }.first { $0.spans(first.time) }
    }

    private static func window(_ period: StockWire.Period?) -> StockTradingWindow? {
        guard let start = period?.start, let end = period?.end, end > start else { return nil }
        return StockTradingWindow(
            start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }

    private static func digits(_ hint: Double?) -> Int? {
        guard let hint, hint.isFinite, hint >= 0 else { return nil }
        return Int(hint.rounded())
    }
}
