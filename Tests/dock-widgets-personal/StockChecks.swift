import Foundation

@MainActor
enum StockChecks {
    private static let english = Locale(identifier: "en_US")
    private static let german = Locale(identifier: "de_DE")

    /// AAPL's sessions in the captured answers: 04:00, 09:30, 16:00 and 20:00 EDT.
    private static let preStart = Date(timeIntervalSince1970: 1_791_187_200)
    private static let open = Date(timeIntervalSince1970: 1_791_207_000)
    private static let close = Date(timeIntervalSince1970: 1_791_230_400)
    private static let postEnd = Date(timeIntervalSince1970: 1_791_244_800)
    private static let midSession = Date(timeIntervalSince1970: 1_791_208_800)

    static func run() {
        ranges()
        chartQuote()
        marketStateBoundaries()
        nullBars()
        tradingDayAxis()
        otherRanges()
        reportedChange()
        chartFailures()
        batchQuotes()
        httpFailures()
        symbols()
        cadence()
        rotation()
        sparkline()
        formatting()
    }

    // MARK: - Requests

    private static func ranges() {
        let t = DockWidgetsPersonalTests.self
        let table = StockRange.allCases.map { "\($0.title) \($0.rangeParameter) \($0.intervalParameter)" }
        t.expect(
            table == ["1D 1d 5m", "5D 5d 1h", "1M 1mo 1d", "6M 6mo 1d", "1Y 1y 1d"],
            "each range maps to Yahoo's range and interval, with daily bars past a week")
        t.expect(
            StockRange.allCases.filter(\.spansTradingDay) == [.day], "only the one-day range fixes its axis")
    }

    // MARK: - Chart answers

    private static func chart(
        _ data: Data, _ range: StockRange = .day, symbol: String = "AAPL", now: Date = midSession
    ) -> StockChartData? {
        try? StockFeed.chart(from: data, symbol: symbol, range: range, now: now)
    }

    private static func chartFailure(
        _ data: Data, symbol: String = "AAPL", now: Date = midSession
    ) -> StockError? {
        do throws(StockError) {
            _ = try StockFeed.chart(from: data, symbol: symbol, range: .day, now: now)
            return nil
        } catch {
            return error
        }
    }

    private static func chartQuote() {
        let t = DockWidgetsPersonalTests.self
        guard let data = chart(StockFixtures.appleDay) else {
            t.expect(false, "a captured one-day chart parses")
            return
        }
        let quote = data.quote
        t.expect(quote.symbol == "AAPL" && quote.name == "Apple Inc.", "the quote names the instrument")
        t.expect(quote.currency == "USD" && quote.price == 333.923, "price and currency come from the meta")
        t.expect(quote.previousClose == 333.69, "a one-day chart's previous close is the meta's")
        t.expect(abs((quote.change ?? 0) - 0.233) < 1e-9, "the day change is Yahoo's own figure")
        t.expect(quote.percentChange == 0.07 && quote.direction == .up, "a gain reads as up")
        t.expect(
            quote.dayHigh == 336.19 && quote.dayLow == 331.65 && quote.yearHigh == 345.34
                && quote.yearLow == 243.42 && quote.volume == 3_907_731,
            "the stats row's figures are read from the meta")
        t.expect(quote.open == 332.7950134277344, "a day's open is its first bar's open")
        t.expect(quote.fractionDigits == 2, "Yahoo's priceHint sets the decimals")
        t.expect(quote.timeZone.identifier == "America/New_York", "the exchange's own zone is kept")
        t.expect(data.series.points.count == 7, "every bar with a close is a point")
        t.expect(
            data.series.points.first?.time == open
                && data.series.points.last?.time == Date(timeIntervalSince1970: 1_791_208_707),
            "points keep Yahoo's timestamps in order")
        t.expect(
            data.series.axis == StockTradingWindow(start: open, end: close),
            "a one-day chart spans the regular session")
        t.expect(data.fetchedAt == midSession && data.range == .day, "the fetch records when and what")
    }

    private static func marketStateBoundaries() {
        let t = DockWidgetsPersonalTests.self
        func state(_ now: Date) -> StockMarketState? {
            chart(StockFixtures.appleDay, now: now)?.quote.marketState
        }
        let second: TimeInterval = 1
        t.expect(state(preStart.addingTimeInterval(-second)) == .closed, "before pre-market it is closed")
        t.expect(state(preStart) == .pre, "pre-market opens on its first second")
        t.expect(state(open.addingTimeInterval(-second)) == .pre, "the last second before the bell is pre")
        t.expect(state(open) == .regular, "the bell opens the regular session")
        t.expect(state(close.addingTimeInterval(-second)) == .regular, "the last second is still open")
        t.expect(state(close) == .post, "at the closing bell the session is over")
        t.expect(state(postEnd.addingTimeInterval(-second)) == .post, "after-hours runs to its end")
        t.expect(state(postEnd) == .closed, "once after-hours ends the market is closed")

        let moments = [preStart, open - second, open, close - second, close, postEnd]
        let decided = moments.compactMap(state).map { StockCadence.interval(for: [$0]) }
        t.expect(
            decided == [900, 900, 60, 60, 900, 900],
            "the refresh cadence is brisk only while the regular session runs")

        let yahoo: [(String?, StockMarketState)] = [
            ("REGULAR", .regular), ("PRE", .pre), ("PREPRE", .closed), ("POST", .post),
            ("POSTPOST", .closed), ("CLOSED", .closed), ("regular", .regular), (nil, .closed), ("", .closed),
        ]
        t.expect(
            yahoo.allSatisfy { StockMarketState(yahoo: $0.0) == $0.1 },
            "Yahoo's marketState names map onto four states, the dead hours being closed")
        let quiet: [StockMarketState] = [.pre, .post, .closed]
        t.expect(
            StockMarketState.regular.isOpen && !quiet.contains(where: \.isOpen),
            "only the regular session is open")
    }

    private static func nullBars() {
        let t = DockWidgetsPersonalTests.self
        guard let data = chart(StockFixtures.tokyoDay, symbol: "7203.T") else {
            t.expect(false, "a chart with null closes parses")
            return
        }
        let times = data.series.points.map(\.time.timeIntervalSince1970)
        t.expect(data.series.points.count == 6, "null closes are dropped, 4 of 10 here")
        t.expect(
            data.series.points.map(\.close) == [2885.0, 2889.5, 2889.5, 2892.5, 2898.0, 2893.5],
            "the surviving closes keep their order")
        t.expect(times == times.sorted() && Set(times).count == times.count, "times stay strictly rising")
        t.expect(
            times == [1_791_158_400, 1_791_158_700, 1_791_167_400, 1_791_171_000, 1_791_181_200, 1_791_181_800],
            "each close keeps its own bar's time, so the lunch break stays a gap")
        t.expect(
            data.quote.currency == "JPY" && data.quote.timeZone.identifier == "Asia/Tokyo",
            "a Tokyo quote")
        t.expect(data.quote.open == 2873.5, "a day's open is its first bar's open, not its close")

        let sparse = Data(
            #"""
            {"chart":{"result":[{"meta":{"currency":"USD","regularMarketPrice":10,"previousClose":9},
            "timestamp":[1000,null,3000,4000],
            "indicators":{"quote":[{"open":[null,9.5,9.6],"close":[9.5,null,null]}]}}],"error":null}}
            """#.utf8)
        let parsed = chart(sparse, symbol: "XYZ")
        t.expect(parsed?.series.points.count == 1, "mismatched array lengths and nulls cannot invent a bar")
        t.expect(parsed?.quote.open == 9.5, "the open is the first one that is not null")
    }

    private static func tradingDayAxis() {
        let t = DockWidgetsPersonalTests.self
        guard let apple = chart(StockFixtures.appleDay), let tokyo = chart(StockFixtures.tokyoDay, symbol: "7203.T")
        else {
            t.expect(false, "both one-day charts parse")
            return
        }
        let morning = StockSparkline(series: apple.series)
        t.expect(morning.points.first?.x == 0, "the first bar sits at the open")
        let lastX = morning.points.last?.x ?? 1
        t.expect(
            abs(lastX - 1707.0 / 23400.0) < 1e-9,
            "seven bars of a 78-bar day fill only the left of the axis: the future stays empty")

        let finished = StockSparkline(series: tokyo.series)
        let xs = finished.points.map(\.x)
        let seconds: [Double] = [0, 300, 9000, 12600, 22800, 23400]
        t.expect(xs.last == 1, "a bar stamped at the close reaches the right edge")
        t.expect(
            zip(xs, seconds).allSatisfy { abs($0 - $1 / 23400) < 1e-9 },
            "x is time in the session, not the bar's index")
        t.expect((xs[2] - xs[1]) > 0.35, "the lunch break is a wide gap, not squeezed shut")

        let bars = [1000.0, 1300, 1600]
        let stale = day(bars: bars, current: (90_000, 95_000), traded: (90_000, 95_000))
        t.expect(
            chart(stale)?.series.axis == nil,
            "a session window that does not hold the bars is not trusted")
        t.expect(
            chart(stale).map { StockSparkline(series: $0.series).points.last?.x } == 1,
            "without an axis the bars fill the width")

        let weekend = day(bars: bars, current: (90_000, 95_000), traded: (900, 5000))
        t.expect(
            chart(weekend)?.series.axis == StockTradingWindow(
                start: Date(timeIntervalSince1970: 900), end: Date(timeIntervalSince1970: 5000)),
            "the data's own trading day wins over a current period that has moved on")

        let current = day(bars: bars, current: (900, 5000), traded: nil)
        t.expect(
            chart(current)?.series.axis == StockTradingWindow(
                start: Date(timeIntervalSince1970: 900), end: Date(timeIntervalSince1970: 5000)),
            "with no trading-periods list the current period holds the axis")
        let oldShape = day(
            bars: bars, current: (900, 5000),
            tradingPeriodsJSON: #"{"regular":[[{"start":1,"end":2}]]}"#)
        t.expect(
            chart(oldShape)?.series.axis?.start == Date(timeIntervalSince1970: 900),
            "a trading-periods list in some other shape is ignored, not fatal")
        let moved = day(bars: bars, current: (90_000, 95_000), traded: nil)
        t.expect(
            chart(moved, now: Date(timeIntervalSince1970: 1200))?.quote.marketState == .closed,
            "a current period that is not now leaves the market closed")
    }

    /// A one-day chart answer in Yahoo's shape, with the windows and bars chosen by the caller.
    private static func day(
        bars: [Double], current: (Double, Double), traded: (Double, Double)?
    ) -> Data {
        let list = traded.map { #"[[{"start":\#($0.0),"end":\#($0.1)}]]"# } ?? "null"
        return day(bars: bars, current: current, tradingPeriodsJSON: list)
    }

    private static func day(
        bars: [Double], current: (Double, Double), tradingPeriodsJSON: String
    ) -> Data {
        let times = bars.map { String(Int($0)) }.joined(separator: ",")
        let closes = bars.indices.map { String(10 + $0) }.joined(separator: ",")
        return Data(
            #"""
            {"chart":{"result":[{"meta":{"currency":"USD","regularMarketPrice":12,"previousClose":9,
            "currentTradingPeriod":{"regular":{"start":\#(current.0),"end":\#(current.1)}},
            "tradingPeriods":\#(tradingPeriodsJSON)},
            "timestamp":[\#(times)],"indicators":{"quote":[{"close":[\#(closes)]}]}}],"error":null}}
            """#.utf8)
    }

    private static func otherRanges() {
        let t = DockWidgetsPersonalTests.self
        if let week = chart(StockFixtures.appleWeek, .fiveDays) {
            t.expect(week.series.axis == nil, "only a one-day chart has a session axis")
            t.expect(week.series.points.count == 8, "five-day bars all have closes")
            t.expect(
                week.quote.previousClose == 333.69,
                "a five-day meta still carries the day's previous close")
            t.expect(week.quote.open == nil, "a multi-day chart has no single day's open")
            let spread = StockSparkline(series: week.series).points.map(\.x)
            t.expect(
                spread.first == 0 && spread.last == 1 && zip(spread, spread.dropFirst()).allSatisfy { $1 > $0 },
                "bars of a longer range spread evenly across the width")
        } else {
            t.expect(false, "a captured five-day chart parses")
        }

        if let month = chart(StockFixtures.appleMonth, .month) {
            t.expect(
                month.quote.previousClose == nil,
                "a month's chartPreviousClose is the close before the range, never the day's")
            t.expect(abs((month.quote.change ?? 0) - 0.135) < 1e-9, "its day change still comes from Yahoo")
            let change = month.series.rangeChange
            let first = month.series.points.first?.close ?? 0
            let last = month.series.points.last?.close ?? 0
            t.expect(abs((change?.amount ?? 0) - (last - first)) < 1e-9, "the range change is first to last")
            t.expect(
                abs((change?.percent ?? 0) - (last - first) / first * 100) < 1e-9,
                "and so is its percent")
        } else {
            t.expect(false, "a captured one-month chart parses")
        }
        let single = StockSeries(points: [.init(time: open, close: 1)], axis: nil)
        t.expect(single.rangeChange == nil, "one bar says nothing about a range")
    }

    private static func reportedChange() {
        let t = DockWidgetsPersonalTests.self
        guard let coin = chart(StockFixtures.bitcoinDay, symbol: "BTC-USD") else {
            t.expect(false, "a captured crypto chart parses")
            return
        }
        t.expect(
            coin.quote.price < (coin.quote.previousClose ?? 0),
            "the coin's price is under its previousClose")
        t.expect(
            (coin.quote.change ?? 0) > 0 && (coin.quote.percentChange ?? 0) > 1 && coin.quote.direction == .up,
            "yet Yahoo's 24-hour gain wins, so the sign matches what yahoo.com shows")
        t.expect(coin.quote.marketState == .regular, "a coin trades all day: its session spans the day")

        let bare = Data(
            #"""
            {"chart":{"result":[{"meta":{"currency":"USD","regularMarketPrice":10,"previousClose":9}}],
            "error":null}}
            """#.utf8)
        let parsed = chart(bare, symbol: "XYZ")
        t.expect(
            abs((parsed?.quote.change ?? 0) - 1) < 1e-9,
            "with no reported figures the change is price - previous")
        t.expect(
            abs((parsed?.quote.percentChange ?? 0) - 100.0 / 9) < 1e-9,
            "and the percent is of the previous close")
        t.expect(
            parsed?.series.points.isEmpty == true && parsed?.series.axis == nil,
            "a chart with no bars is an empty series")
        t.expect(
            parsed?.quote.name == "XYZ" && parsed?.quote.marketState == .closed,
            "no name falls back to the symbol")

        let noPrevious = Data(
            #"{"chart":{"result":[{"meta":{"currency":"USD","regularMarketPrice":10}}],"error":null}}"#.utf8)
        let unknown = chart(noPrevious, symbol: "XYZ")
        t.expect(unknown?.quote.change == nil && unknown?.quote.direction == .flat, "no reference, no change")
    }

    private static func chartFailures() {
        let t = DockWidgetsPersonalTests.self
        t.expect(
            chartFailure(StockFixtures.unknownSymbol, symbol: "ZZZZZZZZQ") == .unknownSymbol("ZZZZZZZZQ"),
            "Yahoo's Not Found error names the symbol the user typed")
        if case .api(let description)? = chartFailure(StockFixtures.rangeUnavailable) {
            t.expect(
                description.hasPrefix("5m data not available"),
                "any other Yahoo error is passed through verbatim")
        } else {
            t.expect(false, "an unprocessable range is Yahoo's own error")
        }
        for (name, body) in [
            ("an empty result", #"{"chart":{"result":[],"error":null}}"#),
            ("a null result", #"{"chart":{"result":null,"error":null}}"#),
            ("a result without a price", #"{"chart":{"result":[{"meta":{"currency":"USD"}}],"error":null}}"#),
        ] {
            t.expect(
                chartFailure(Data(body.utf8), symbol: "AAPL") == .unknownSymbol("AAPL"),
                "\(name) is no quote")
        }
        let garbage = [
            ("html", "<html>Service Unavailable</html>"), ("nothing", ""), ("an object", "{}"),
            ("an array", "[]"),
        ]
        for (name, body) in garbage {
            t.expect(chartFailure(Data(body.utf8)) == .malformed, "\(name) is not an answer")
        }
    }

    // MARK: - Batched quotes

    private static func batch(_ data: Data, _ symbols: [String], now: Date = midSession) -> StockBatch? {
        try? StockFeed.batch(from: data, symbols: symbols, now: now)
    }

    private static func batchFailure(_ data: Data) -> StockError? {
        do throws(StockError) {
            _ = try StockFeed.batch(from: data, symbols: ["AAPL"], now: midSession)
            return nil
        } catch {
            return error
        }
    }

    private static func batchQuotes() {
        let t = DockWidgetsPersonalTests.self
        guard let result = batch(StockFixtures.quotes, ["BTC-USD", "AAPL", "ZZZ", "7203.T"]) else {
            t.expect(false, "a captured batch parses")
            return
        }
        t.expect(
            result.quotes.map(\.symbol) == ["BTC-USD", "AAPL", "7203.T"],
            "quotes come back in the order asked")
        t.expect(
            result.failures == ["ZZZ": .unknownSymbol("ZZZ")],
            "a symbol Yahoo skipped is named as missing")
        guard result.quotes.count == 3 else { return }
        let (coin, apple, tokyo) = (result.quotes[0], result.quotes[1], result.quotes[2])
        t.expect(
            apple.name == "Apple Inc." && apple.marketState == .regular,
            "the market state is Yahoo's own")
        t.expect(
            tokyo.marketState == .closed && tokyo.currency == "JPY",
            "POSTPOST means closed, and the currency is kept")
        t.expect(tokyo.name == "Toyota Motor Corporation", "the long name wins over the shouting short one")
        t.expect(
            abs((apple.percentChange ?? 0) - 0.00299981) < 1e-9 && apple.open == 332.795,
            "the quote row carries its own open and reported change")
        t.expect(
            coin.direction == .up && (coin.previousClose ?? 0) > coin.price,
            "the batch trusts Yahoo's change over previous-close arithmetic too")
        t.expect(apple.volume == 3_916_296 && apple.yearHigh == 345.34, "the stats come from the row")
        t.expect(
            apple.fractionDigits == 2 && apple.timeZone.identifier == "America/New_York",
            "decimals and zone")
        let states = result.quotes.map(\.marketState)
        t.expect(
            StockCadence.interval(for: states) == 60,
            "one open market in a watchlist keeps the whole list brisk")
        t.expect(
            StockCadence.interval(for: [tokyo.marketState]) == 900, "a watchlist of closed markets is lazy")

        t.expect(
            batch(StockFixtures.quotes, ["aapl"])?.quotes.map(\.symbol) == ["AAPL"],
            "symbols match case-insensitively")

        let empty = batch(StockFixtures.quotesEmpty, ["ZZZZZZZZQ"])
        t.expect(
            empty?.quotes.isEmpty == true && empty?.failures["ZZZZZZZZQ"] == .unknownSymbol("ZZZZZZZZQ"),
            "an empty result is every symbol missing, not an error")

        let ragged = Data(
            #"""
            {"quoteResponse":{"result":[
            {"symbol":"AAPL","regularMarketPrice":null,"marketState":"REGULAR"},
            {"symbol":["not","a","string"],"regularMarketPrice":1},
            {"symbol":"MSFT","regularMarketPrice":527.35,"regularMarketPreviousClose":517.53,"marketState":"PRE"},
            {"regularMarketPrice":2}],"error":null}}
            """#.utf8)
        let defended = batch(ragged, ["AAPL", "MSFT"])
        t.expect(
            defended?.quotes.map(\.symbol) == ["MSFT"],
            "a null price, a mistyped row and a nameless one are skipped")
        t.expect(
            defended?.failures["AAPL"] == .unknownSymbol("AAPL"),
            "the null-priced symbol is reported missing")
        t.expect(
            abs((defended?.quotes.first?.change ?? 0) - 9.82) < 1e-9
                && abs((defended?.quotes.first?.percentChange ?? 0) - 9.82 / 517.53 * 100) < 1e-9,
            "a row with no reported change falls back to price against previous close")
        t.expect(defended?.quotes.first?.marketState == .pre, "pre-market is its own state")

        t.expect(
            batchFailure(StockFixtures.quotesUnauthorized) == .unauthorized,
            "a crumb error is recognised by its code")
        t.expect(
            batchFailure(Data("{}".utf8)) == .malformed,
            "a quote answer without a quoteResponse is unreadable")
        t.expect(batchFailure(Data("Too Many Requests".utf8)) == .malformed, "plain text is unreadable")
    }

    // MARK: - HTTP

    private static func httpFailures() {
        let t = DockWidgetsPersonalTests.self
        func error(_ status: Int, _ body: Data = Data(), _ symbol: String? = nil) -> StockError {
            StockFeed.error(status: status, body: body, symbol: symbol)
        }
        t.expect(error(429, Data("Too Many Requests".utf8)) == .rateLimited, "429 is rate limiting")
        t.expect(error(401, StockFixtures.quotesUnauthorized) == .unauthorized, "401 is a refused crumb")
        t.expect(error(403) == .unauthorized, "403 is too")
        t.expect(error(500) == .server(500) && error(503) == .server(503), "5xx names the status")
        t.expect(
            error(404, StockFixtures.unknownSymbol, "ZZZZZZZZQ") == .unknownSymbol("ZZZZZZZZQ"),
            "404 names the symbol")
        t.expect(
            error(404, Data(), "AAPL") == .unknownSymbol("AAPL"),
            "an unexplained 404 for a symbol is still that symbol")
        t.expect(error(404) == .server(404), "an unexplained 404 for nothing in particular is the server's")
        if case .api(let text) = error(422, StockFixtures.rangeUnavailable, "AAPL") {
            t.expect(text.contains("60 days"), "a 422's explanation reaches the user")
        } else {
            t.expect(false, "422 carries Yahoo's own words")
        }

        let all: [StockError] = [
            .noSymbols, .unknownSymbol("X"), .api("A reason."), .rateLimited, .unauthorized, .server(502),
            .offline, .timedOut, .network("The network connection was lost."), .malformed,
        ]
        t.expect(
            all.allSatisfy { !$0.message.isEmpty && $0.errorDescription == $0.message },
            "every failure has words")
        t.expect(StockError.api("A reason.").message == "A reason.", "Yahoo's words are shown as they are")
        t.expect(
            all.filter(\.isTransient) == [.rateLimited, .unauthorized, .server(502), .offline, .timedOut,
                .network("The network connection was lost."), .malformed],
            "only a wrong symbol or an empty setting stays wrong when asked again")
        t.expect(
            all.filter(\.invalidatesCrumb) == [.api("A reason."), .unauthorized, .malformed],
            "a refused or unreadable answer earns a fresh crumb; a rate limit or a lost network does not")
    }

    // MARK: - Settings text

    private static func symbols() {
        let t = DockWidgetsPersonalTests.self
        let table: [(String?, [String])] = [
            ("AAPL, MSFT  googl", ["AAPL", "MSFT", "GOOGL"]),
            ("aapl;msft\ngoog\tamzn", ["AAPL", "MSFT", "GOOG", "AMZN"]),
            ("AAPL AAPL aapl, Aapl", ["AAPL"]),
            ("$", []), ("", []), (nil, []), ("   ,, ;\n", []),
            ("$aapl, $, $$msft", ["AAPL", "MSFT"]),
            (
                "BRK-B ^GSPC EURUSD=X 7203.T M&M.NS BTC-USD",
                ["BRK-B", "^GSPC", "EURUSD=X", "7203.T", "M&M.NS", "BTC-USD"]
            ),
            ("AA!PL, AAPL, \"MSFT\", GO OG", ["AAPL", "GO", "OG"]),
            ("ÄPL, -, ..., AAPL", ["AAPL"]),
            ("ABCDEFGHIJKLMNOPQRSTUVWXYZ, OK", ["OK"]),
            ("ABCDEFGHIJKLMNOPQRSTUVWX", ["ABCDEFGHIJKLMNOPQRSTUVWX"]),
        ]
        for (text, expected) in table {
            t.expect(StockSymbols.parse(text) == expected, "parse(\(text.map { "\"\($0)\"" } ?? "nil")) = \(expected)")
        }
        let many = (1...15).map { "S\($0)" }.joined(separator: ",")
        t.expect(
            StockSymbols.parse(many).count == 12 && StockSymbols.parse(many).last == "S12",
            "a watchlist holds at most 12")
        t.expect(StockSymbols.parse("A A A B C", limit: 2) == ["A", "B"], "duplicates do not use up the cap")
        t.expect(StockSymbols.parse("A B", limit: 0).isEmpty, "a zero cap holds nothing")
        t.expect(StockSymbols.single(" aapl ") == "AAPL", "the Stock symbol is trimmed and uppercased")
        t.expect(StockSymbols.single("msft aapl") == "MSFT", "the first of several wins")
        t.expect(
            StockSymbols.single("$") == nil && StockSymbols.single(nil) == nil && StockSymbols.single("") == nil,
            "garbage is no symbol")
        t.expect(StockSymbols.single("$tsla") == "TSLA", "a cashtag is its ticker")
    }

    // MARK: - Schedule

    private static func cadence() {
        let t = DockWidgetsPersonalTests.self
        t.expect(StockCadence.interval(for: []) == 900, "no quotes yet means the lazy pace")
        t.expect(StockCadence.interval(for: [.closed, .pre, .post]) == 900, "pre, post and closed are lazy")
        t.expect(StockCadence.interval(for: [.closed, .regular]) == 60, "any open market makes it brisk")
        t.expect(
            StockCadence.interval(after: .offline) == 60 && StockCadence.interval(after: .rateLimited) == 60,
            "a failure that may pass is retried soon")
        t.expect(
            StockCadence.interval(after: .unknownSymbol("X")) == 900 && StockCadence.interval(after: .noSymbols) == 900,
            "a wrong setting is not hammered")
        let now = midSession
        t.expect(StockCadence.delay(nextFetch: nil, now: now) == 0, "nothing fetched yet is due at once")
        t.expect(
            StockCadence.delay(nextFetch: now.addingTimeInterval(42), now: now) == 42,
            "a fresh tile waits out the rest")
        t.expect(
            StockCadence.delay(nextFetch: now.addingTimeInterval(-5), now: now) == 0,
            "an overdue one does not wait")
        t.expect(StockCadence.delay(nextFetch: now, now: now) == 0, "due exactly now is due")
    }

    private static func rotation() {
        let t = DockWidgetsPersonalTests.self
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let indexes = (0..<9).map { StockRotation.index(at: start.addingTimeInterval(Double($0) * 5), count: 4) }
        t.expect(indexes == [0, 1, 2, 3, 0, 1, 2, 3, 0], "the compact tile steps through the list every 5 s")
        t.expect(
            StockRotation.index(at: start.addingTimeInterval(4.99), count: 4)
                == StockRotation.index(at: start, count: 4),
            "it holds still inside a step")
        t.expect(
            StockRotation.index(at: start, count: 0) == 0 && StockRotation.index(at: start, count: 1) == 0,
            "no list to rotate")
        let before = StockRotation.index(at: Date(timeIntervalSinceReferenceDate: -7), count: 4)
        t.expect((0..<4).contains(before), "a date before the reference epoch still lands in range")
        t.expect(
            StockRotation.index(at: start, count: 3, period: 0) == 0,
            "a zero period does not divide by zero")
    }

    // MARK: - Sparkline

    private static func sparkline() {
        let t = DockWidgetsPersonalTests.self
        guard let apple = chart(StockFixtures.appleDay) else { return }
        let plain = StockSparkline(series: apple.series)
        let ys = plain.points.map(\.y)
        t.expect(ys.min() == 0 && ys.max() == 1, "the lowest close is 0 and the highest is 1")
        t.expect(plain.baseline == nil && plain.isDrawable, "no reference line unless asked")
        t.expect(
            zip(plain.points, apple.series.points).allSatisfy { $0.value == $1.close && $0.time == $1.time },
            "points keep the real value and time for a hover to read")

        let marked = StockSparkline(series: apple.series, baseline: 333.69)
        t.expect((0...1).contains(marked.baseline ?? -1), "a reference inside the range stays on the chart")
        let below = StockSparkline(series: apple.series, baseline: 300)
        t.expect(
            below.baseline == 0 && (below.points.map(\.y).min() ?? 0) > 0,
            "a distant reference stretches the scale to hold it")
        let above = StockSparkline(series: apple.series, baseline: 400)
        t.expect(above.baseline == 1, "and so does one above")

        let flat = StockSeries(
            points: [.init(time: open, close: 5), .init(time: open.addingTimeInterval(60), close: 5)], axis: nil)
        t.expect(
            StockSparkline(series: flat).points.map(\.y) == [0.5, 0.5],
            "a flat line is drawn mid-chart, not on an edge")
        let lone = StockSparkline(series: StockSeries(points: [.init(time: open, close: 5)], axis: nil))
        t.expect(!lone.isDrawable && lone.points.count == 1, "one bar is not a line")
        let none = StockSparkline(series: StockSeries(points: [], axis: nil))
        t.expect(
            !none.isDrawable && none.points.isEmpty && none.nearestIndex(toX: 0.5) == nil,
            "no bars, nothing to draw or hover")

        guard let tokyo = chart(StockFixtures.tokyoDay, symbol: "7203.T") else { return }
        let day = StockSparkline(series: tokyo.series)
        t.expect(day.nearestIndex(toX: 0.5) == 3, "a hover snaps to the nearest real bar")
        t.expect(
            day.nearestIndex(toX: -3) == 0 && day.nearestIndex(toX: 9) == day.points.count - 1,
            "and clamps off either end")
        t.expect(day.nearestIndex(toX: 0.15) == 1, "a hover in the gap picks the closer side")
    }

    // MARK: - Formatting

    /// ICU separates a clock from AM/PM, and a number from its currency, with a no-break space.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func formatting() {
        let t = DockWidgetsPersonalTests.self
        let en = english
        t.expect(StockFormat.percent(0.0698, locale: en) == "+0.07%", "a gain carries a plus")
        t.expect(StockFormat.percent(-1.234, locale: en) == "-1.23%", "a loss carries a minus")
        t.expect(
            StockFormat.percent(0, locale: en) == "0.00%" && StockFormat.percent(-0.0, locale: en) == "0.00%",
            "zero has no sign, even a negative one")
        t.expect(StockFormat.percent(-0.001, locale: en) == "0.00%", "a loss too small to show has no minus")
        t.expect(StockFormat.percent(0.004, locale: en) == "0.00%", "nor does a gain")
        t.expect(StockFormat.percent(1234.5678, locale: en) == "+1,234.57%", "a huge move groups its digits")
        t.expect(
            [nil, .nan, .infinity].allSatisfy { StockFormat.percent($0, locale: en) == "—" },
            "no figure is a dash")
        t.expect(
            StockFormat.percent(1.23, locale: german).hasPrefix("+1,23"),
            "the locale picks the decimal mark")
        t.expect(
            StockFormat.roundedPercent(-0.004) == 0 && StockFormat.roundedPercent(-0.004).sign == .plus,
            "rounding never leaves a negative zero")
        t.expect(
            StockDirection(percent: -0.004) == .flat && StockDirection(percent: 0.006) == .up
                && StockDirection(percent: -0.006) == .down,
            "direction is judged on what is shown")
        t.expect(
            StockDirection(percent: nil) == .flat && StockDirection(percent: .nan) == .flat,
            "no figure, no direction")

        t.expect(
            StockFormat.price(333.923, currency: "USD", fractionDigits: 2, locale: en) == "$333.92",
            "a stock price at Yahoo's decimals")
        t.expect(
            StockFormat.price(86466.64, currency: "USD", fractionDigits: 2, locale: en) == "$86,466.64",
            "a big price groups thousands")
        t.expect(
            StockFormat.price(703412.5, currency: "USD", locale: en) == "$703,412.50",
            "no hint: two decimals from a dollar up")
        t.expect(
            StockFormat.price(1.1193, currency: "USD", fractionDigits: 4, locale: en) == "$1.1193",
            "an FX rate keeps its four decimals")
        t.expect(
            StockFormat.price(2893.5, currency: "JPY", fractionDigits: 2, locale: en) == "¥2,893.50",
            "a yen price follows the hint")
        t.expect(
            StockFormat.price(2894, currency: "JPY", locale: en) == "¥2,894",
            "yen has no minor unit by default")
        t.expect(
            StockFormat.price(2893.5, currency: "JPY", locale: en) == "¥2,893.5",
            "but a half yen is still shown")
        t.expect(
            StockFormat.price(2894, currency: "JPY", locale: Locale(identifier: "en_AU")) == "¥2,894",
            "the narrow symbol keeps a price short where the locale would write JP¥")
        t.expect(
            StockFormat.price(0.00001234, currency: "USD", fractionDigits: 5, locale: en) == "$0.00001234",
            "a tiny price shows significant digits, not zeros")
        t.expect(
            StockFormat.price(0.5, currency: "USD", locale: en) == "$0.50",
            "a sub-dollar price keeps two digits")
        t.expect(
            StockFormat.price(0.12345, currency: "USD", locale: en) == "$0.1234",
            "and up to four significant")
        t.expect(
            StockFormat.price(127.7, currency: "GBp", fractionDigits: 2, locale: en) == "127.70 GBp",
            "pence is not an ISO code, so it trails the number")
        t.expect(
            plain(StockFormat.price(1234.5, currency: "EUR", fractionDigits: 2, locale: german)) == "1.234,50 €",
            "euros in German")
        t.expect(StockFormat.price(0, currency: "USD", locale: en) == "$0.00", "zero is a price too")
        t.expect(
            [nil, .nan].allSatisfy { StockFormat.price($0, currency: "USD", locale: en) == "—" },
            "no price is a dash")
        t.expect(
            StockFormat.price(12, currency: "", locale: en) == "12.00",
            "a quote without a currency is a bare number")

        t.expect(
            StockFormat.change(0.233, price: 333.923, currency: "USD", fractionDigits: 2, locale: en) == "+$0.23",
            "a gain in dollars")
        t.expect(
            StockFormat.change(-97.5, price: 86466.64, currency: "USD", fractionDigits: 2, locale: en) == "-$97.50",
            "a loss in dollars")
        t.expect(
            StockFormat.change(-0.003, price: 333.9, currency: "USD", fractionDigits: 2, locale: en) == "$0.00",
            "a move below a cent has no sign")
        t.expect(
            StockFormat.change(-0.0, price: 333.9, currency: "USD", fractionDigits: 2, locale: en) == "$0.00",
            "negative zero has none either")
        t.expect(
            StockFormat.change(0.003, price: 333.9, currency: "USD", locale: en) == "$0.00",
            "a cent on a stock never reads +$0.003")
        t.expect(
            StockFormat.change(37, price: 2893.5, currency: "JPY", fractionDigits: 2, locale: en) == "+¥37.00",
            "a gain in yen")
        t.expect(
            StockFormat.change(0.0000012, price: 0.00001234, currency: "USD", locale: en) == "+$0.0000012",
            "a tiny coin's move keeps its digits")
        t.expect(StockFormat.change(nil, price: 1, currency: "USD", locale: en) == "—", "no change is a dash")

        t.expect(StockFormat.volume(3_907_731, locale: en) == "3.91M", "volume in millions")
        t.expect(StockFormat.volume(25_379_489_792, locale: en) == "25.4B", "volume in billions")
        t.expect(
            StockFormat.volume(1234, locale: en) == "1.23K" && StockFormat.volume(12, locale: en) == "12"
                && StockFormat.volume(0, locale: en) == "0",
            "small volumes")
        t.expect(StockFormat.volume(nil, locale: en) == "—", "no volume is a dash")

        let new_york = TimeZone(identifier: "America/New_York") ?? .current
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let instant = Date(timeIntervalSince1970: 1_791_208_707)
        t.expect(
            plain(StockFormat.pointTime(instant, range: .day, timeZone: new_york, locale: en)) == "9:58 AM",
            "a day's bar is a clock time in the exchange's zone")
        t.expect(
            plain(StockFormat.pointTime(instant, range: .day, timeZone: tokyo, locale: en)) == "10:58 PM",
            "in another zone, another clock")
        t.expect(
            plain(StockFormat.pointTime(instant, range: .fiveDays, timeZone: new_york, locale: en)) == "Mon 9:58 AM",
            "a week's bar adds its weekday")
        t.expect(
            plain(StockFormat.pointTime(instant, range: .month, timeZone: new_york, locale: en)) == "Oct 5",
            "a month's bar is a date")
        t.expect(
            plain(StockFormat.pointTime(instant, range: .year, timeZone: new_york, locale: en)) == "Oct 5, 2026",
            "a year's bar adds the year")

        if let apple = chart(StockFixtures.appleDay) {
            let day = StockFormat.axisLabels(for: apple.series, range: .day, timeZone: apple.quote.timeZone, locale: en)
            t.expect(
                plain(day?.leading ?? "") == "9:30 AM" && plain(day?.trailing ?? "") == "4:00 PM",
                "a day's axis is labelled with the session's bells")
            t.expect(
                plain(StockFormat.spoken(apple.quote, locale: en)) == "Apple Inc., $333.92, up 0.07%, Market open",
                "VoiceOver hears the name, price, direction and market state")
        }
        if let week = chart(StockFixtures.appleWeek, .fiveDays) {
            let labels = StockFormat.axisLabels(
                for: week.series, range: .fiveDays, timeZone: week.quote.timeZone, locale: en)
            t.expect(
                plain(labels?.leading ?? "") == "Tue 9:30 AM" && plain(labels?.trailing ?? "") == "Mon 9:59 AM",
                "a longer range is labelled by its first and last bar")
        }
        t.expect(
            StockFormat.axisLabels(
                for: StockSeries(points: [], axis: nil), range: .month, timeZone: new_york, locale: en) == nil,
            "an empty series has no axis")
    }
}

private enum StockFixtures {
    /// AAPL, range=1d interval=5m, captured mid-session: 7 bars of the 78 in a day.
    static let appleDay = Data(
        #"""
        {"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL","exchangeName":"NMS",
        "fullExchangeName":"NasdaqGS","instrumentType":"EQUITY","firstTradeDate":345479400,
        "regularMarketTime":1791208707,"hasPrePostMarketData":true,"gmtoffset":-14400,"timezone":"EDT",
        "exchangeTimezoneName":"America/New_York","regularMarketPrice":333.923,
        "regularMarketChangePercent":0.07,"fulldayPrice":333.923,"fulldayChange":0.233,
        "fulldayChangePercent":0.07,"fiftyTwoWeekHigh":345.34,"fiftyTwoWeekLow":243.42,
        "regularMarketDayHigh":336.19,"regularMarketDayLow":331.65,"regularMarketVolume":3907731,
        "longName":"Apple Inc.","shortName":"Apple Inc.","chartPreviousClose":333.69,"previousClose":333.69,
        "scale":3,"priceHint":2,"currentTradingPeriod":{"pre":{"timezone":"EDT","start":1791187200,
        "end":1791207000,"gmtoffset":-14400},"regular":{"timezone":"EDT","start":1791207000,
        "end":1791230400,"gmtoffset":-14400},"post":{"timezone":"EDT","start":1791230400,"end":1791244800,
        "gmtoffset":-14400}},"tradingPeriods":[[{"timezone":"EDT","start":1791207000,"end":1791230400,
        "gmtoffset":-14400}]],"dataGranularity":"5m","range":"1d"},"timestamp":[1791207000,1791207300,
        1791207600,1791207900,1791208200,1791208500,1791208707],
        "indicators":{"quote":[{"open":[332.7950134277344,336.0899963378906,335.3800048828125,
        335.20001220703125,334.7699890136719,334.9100036621094,333.9226989746094],"volume":[1810280,497004,
        348316,704863,292904,205140,0],"low":[331.6499938964844,334.7300109863281,334.5799865722656,
        334.54998779296875,334.2699890136719,334.18011474609375,333.9226989746094],
        "close":[336.0736083984375,335.3900146484375,335.2250061035156,334.7300109863281,334.92999267578125,
        334.2749938964844,333.9226989746094],"high":[336.19000244140625,336.1099853515625,335.3800048828125,
        336.0799865722656,335.2699890136719,334.9800109863281,333.9226989746094]}]}}],"error":null}}
        """#.utf8)

    /// 7203.T, range=1d interval=5m, cut to 10 bars; the lunch break is null closes.
    static let tokyoDay = Data(
        #"""
        {"chart":{"result":[{"meta":{"currency":"JPY","symbol":"7203.T","exchangeName":"JPX",
        "fullExchangeName":"Tokyo","instrumentType":"EQUITY","firstTradeDate":925948800,
        "regularMarketTime":1791181800,"hasPrePostMarketData":false,"gmtoffset":32400,"timezone":"JST",
        "exchangeTimezoneName":"Asia/Tokyo","regularMarketPrice":2893.5,"regularMarketChangePercent":1.295,
        "fulldayPrice":2893.5,"fulldayChange":37.0,"fulldayChangePercent":1.295,"fiftyTwoWeekHigh":4000.0,
        "fiftyTwoWeekLow":2686.0,"regularMarketDayHigh":2900.0,"regularMarketDayLow":2867.5,
        "regularMarketVolume":23901000,"longName":"Toyota Motor Corporation",
        "shortName":"TOYOTA MOTOR CORP","chartPreviousClose":2856.5,"previousClose":2856.5,"scale":3,
        "priceHint":2,"currentTradingPeriod":{"pre":{"timezone":"JST","end":1791158400,"start":1791158400,
        "gmtoffset":32400},"regular":{"timezone":"JST","end":1791181800,"start":1791158400,
        "gmtoffset":32400},"post":{"timezone":"JST","end":1791181800,"start":1791181800,"gmtoffset":32400}},
        "tradingPeriods":[[{"timezone":"JST","end":1791181800,"start":1791158400,"gmtoffset":32400}]],
        "dataGranularity":"5m","range":"1d"},"timestamp":[1791158400,1791158700,1791167400,1791167700,
        1791168000,1791170700,1791171000,1791181200,1791181500,1791181800],
        "indicators":{"quote":[{"open":[2873.5,2885.0,2888.5,null,null,null,2888.5,2899.0,null,2893.5],
        "volume":[985400,662700,55700,null,null,null,703800,642700,null,0],"high":[2888.0,2890.5,2889.5,
        null,null,null,2896.5,2899.5,null,2893.5],"low":[2867.5,2882.0,2888.5,null,null,null,2888.5,2896.0,
        null,2893.5],"close":[2885.0,2889.5,2889.5,null,null,null,2892.5,2898.0,null,2893.5]}]}}],
        "error":null}}
        """#.utf8)

    /// AAPL, range=5d interval=1h, cut to 8 bars across five sessions.
    static let appleWeek = Data(
        #"""
        {"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL","exchangeName":"NMS",
        "fullExchangeName":"NasdaqGS","instrumentType":"EQUITY","firstTradeDate":345479400,
        "regularMarketTime":1791208756,"hasPrePostMarketData":true,"gmtoffset":-14400,"timezone":"EDT",
        "exchangeTimezoneName":"America/New_York","regularMarketPrice":333.791,
        "regularMarketChangePercent":0.03,"fulldayPrice":333.791,"fulldayChange":0.101,
        "fulldayChangePercent":0.03,"fiftyTwoWeekHigh":345.34,"fiftyTwoWeekLow":243.42,
        "regularMarketDayHigh":336.19,"regularMarketDayLow":331.65,"regularMarketVolume":3989747,
        "longName":"Apple Inc.","shortName":"Apple Inc.","chartPreviousClose":338.4,"previousClose":333.69,
        "scale":3,"priceHint":2,"currentTradingPeriod":{"pre":{"timezone":"EDT","end":1791207000,
        "start":1791187200,"gmtoffset":-14400},"regular":{"timezone":"EDT","end":1791230400,
        "start":1791207000,"gmtoffset":-14400},"post":{"timezone":"EDT","end":1791244800,"start":1791230400,
        "gmtoffset":-14400}},"tradingPeriods":[[{"timezone":"EDT","end":1790712000,"start":1790688600,
        "gmtoffset":-14400}],[{"timezone":"EDT","end":1790798400,"start":1790775000,"gmtoffset":-14400}],
        [{"timezone":"EDT","end":1790884800,"start":1790861400,"gmtoffset":-14400}],[{"timezone":"EDT",
        "end":1790971200,"start":1790947800,"gmtoffset":-14400}],[{"timezone":"EDT","end":1791230400,
        "start":1791207000,"gmtoffset":-14400}]],"dataGranularity":"1h","range":"5d"},
        "timestamp":[1790688600,1790692200,1790775000,1790778600,1790861400,1790951400,1791207000,
        1791208756],"indicators":{"quote":[{"close":[332.07000732421875,331.75,338.1499938964844,
        337.3599853515625,330.9200134277344,332.34930419921875,333.68499755859375,333.79071044921875],
        "low":[331.6300048828125,331.510009765625,330.1401062011719,336.9800109863281,328.3699951171875,
        331.0799865722656,331.6499938964844,333.79071044921875],"open":[333.2078857421875,
        332.06500244140625,330.79998779296875,338.19000244140625,330.1700134277344,334.2850036621094,
        332.7950134277344,333.79071044921875],"high":[334.5367126464844,332.94000244140625,339.5,
        339.2799987792969,332.4815979003906,334.45001220703125,336.19000244140625,333.79071044921875],
        "volume":[7451686,4041894,11162786,4477240,7382621,5089535,3960224,0]}]}}],"error":null}}
        """#.utf8)

    /// AAPL, range=1mo interval=1d, cut to 5 bars; the meta has no previousClose.
    static let appleMonth = Data(
        #"""
        {"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL","exchangeName":"NMS",
        "fullExchangeName":"NasdaqGS","instrumentType":"EQUITY","firstTradeDate":345479400,
        "regularMarketTime":1791208756,"hasPrePostMarketData":true,"gmtoffset":-14400,"timezone":"EDT",
        "exchangeTimezoneName":"America/New_York","regularMarketPrice":333.825,
        "regularMarketChangePercent":0.04,"fulldayPrice":333.825,"fulldayChange":0.135,
        "fulldayChangePercent":0.04,"fiftyTwoWeekHigh":345.34,"fiftyTwoWeekLow":243.42,
        "regularMarketDayHigh":336.19,"regularMarketDayLow":331.65,"regularMarketVolume":3988528,
        "longName":"Apple Inc.","shortName":"Apple Inc.","chartPreviousClose":319.97,"priceHint":2,
        "currentTradingPeriod":{"pre":{"timezone":"EDT","end":1791207000,"start":1791187200,
        "gmtoffset":-14400},"regular":{"timezone":"EDT","end":1791230400,"start":1791207000,
        "gmtoffset":-14400},"post":{"timezone":"EDT","end":1791244800,"start":1791230400,
        "gmtoffset":-14400}},"dataGranularity":"1d","range":"1mo"},"timestamp":[1788874200,1789479000,
        1790083800,1790688600,1791207000],"indicators":{"quote":[{"open":[317.1000061035156,
        330.1400146484375,340.1400146484375,336.9700012207031,332.7950134277344],"volume":[35477100,
        31748200,40711800,38478000,3988528],"high":[320.70001220703125,331.7799987792969,345.3399963378906,
        337.0899963378906,336.19000244140625],"low":[314.8999938964844,328.3500061035156,338.75,
        328.70001220703125,331.6499938964844],"close":[316.2200012207031,331.3399963378906,339.75,
        329.3999938964844,333.82501220703125]}],"adjclose":[{"adjclose":[316.2200012207031,
        315.3399963378906,326.57000732421875,332.2699890136719,333.0799865722656,331.3399963378906,
        332.4100036621094,337.0,336.1300048828125,338.9800109863281,339.75,337.0199890136719,
        335.9200134277344,341.07000732421875,338.3999938964844,329.3999938964844,333.0199890136719,
        330.32000732421875,333.69000244140625,333.82501220703125]}]}}],"error":null}}
        """#.utf8)

    /// BTC-USD, range=1d interval=5m, cut to 7 bars; a reported gain beside a lower price.
    static let bitcoinDay = Data(
        #"""
        {"chart":{"result":[{"meta":{"currency":"USD","symbol":"BTC-USD","exchangeName":"CCC",
        "fullExchangeName":"CCC","instrumentType":"CRYPTOCURRENCY","firstTradeDate":1410912000,
        "regularMarketTime":1791208700,"hasPrePostMarketData":false,"gmtoffset":0,"timezone":"UTC",
        "exchangeTimezoneName":"UTC","regularMarketPrice":86466.64,"regularMarketChangePercent":1.446,
        "fulldayPrice":86466.64,"fulldayChange":1232.773,"fulldayChangePercent":1.446,
        "fiftyTwoWeekHigh":126198.07,"fiftyTwoWeekLow":57747.766,"regularMarketDayHigh":86929.66,
        "regularMarketDayLow":85443.79,"regularMarketVolume":25263355904,"longName":"Bitcoin USD",
        "shortName":"Bitcoin USD","chartPreviousClose":86513.38,"previousClose":86513.38,"scale":3,
        "priceHint":2,"currentTradingPeriod":{"pre":{"timezone":"UTC","end":1791158400,"start":1791158400,
        "gmtoffset":0},"regular":{"timezone":"UTC","end":1791244740,"start":1791158400,"gmtoffset":0},
        "post":{"timezone":"UTC","end":1791244740,"start":1791244740,"gmtoffset":0}},
        "tradingPeriods":[[{"timezone":"UTC","end":1791244740,"start":1791158400,"gmtoffset":0}]],
        "dataGranularity":"5m","range":"1d"},"timestamp":[1791158400,1791158700,1791170400,1791182400,
        1791194400,1791208500,1791208700],"indicators":{"quote":[{"volume":[813056,356828160,76206080,
        29171712,10416128,24342528,0],"high":[86488.90625,86494.9375,86403.6015625,85848.7890625,86049.25,
        86460.2734375,86466.640625],"low":[86310.953125,86390.203125,86294.0,85770.4296875,85928.3515625,
        86285.203125,86466.640625],"close":[86434.7109375,86390.203125,86403.6015625,85794.3203125,
        86027.3984375,86460.2734375,86466.640625],"open":[86471.703125,86430.0,86392.53125,85826.28125,
        85961.2890625,86334.5390625,86466.640625]}]}}],"error":null}}
        """#.utf8)

    /// HTTP 404 for a symbol Yahoo does not know.
    static let unknownSymbol = Data(
        #"""
        {"chart":{"result":null,"error":{"code":"Not Found",
        "description":"No data found, symbol may be delisted"}}}
        """#.utf8)

    /// HTTP 422 for 5m bars further back than 60 days.
    static let rangeUnavailable = Data(
        #"""
        {"chart":{"result":null,"error":{"code":"Unprocessable Entity","description":"5m data not available \#
        for startTime=1728136756 and endTime=1791208756. The requested range must be within the last 60 days."}}}
        """#.utf8)

    /// v7/finance/quote for a symbol Yahoo does not know.
    static let quotesEmpty = Data(
        #"""
        {"quoteResponse":{"result":[],"error":null}}
        """#.utf8)

    /// HTTP 401 from v7/finance/quote without a crumb.
    static let quotesUnauthorized = Data(
        #"""
        {"finance":{"result":null,"error":{"code":"Unauthorized","description":"User is unable to access this \#
        feature - https://bit.ly/yahoo-finance-api-feedback"}}}
        """#.utf8)

    /// v7/finance/quote for AAPL, 7203.T and BTC-USD, cut to the fields that matter.
    static let quotes = Data(
        #"""
        {"quoteResponse":{"result":[{"language":"en-US","region":"US","quoteType":"EQUITY","symbol":"AAPL",
        "shortName":"Apple Inc.","longName":"Apple Inc.","currency":"USD","marketState":"REGULAR",
        "exchangeTimezoneName":"America/New_York","priceHint":2,"regularMarketPrice":333.7,
        "regularMarketChange":0.010009766,"regularMarketChangePercent":0.00299981,
        "regularMarketPreviousClose":333.69,"regularMarketOpen":332.795,"regularMarketDayHigh":336.19,
        "regularMarketDayLow":331.65,"regularMarketVolume":3916296,"fiftyTwoWeekHigh":345.34,
        "fiftyTwoWeekLow":243.42,"epsForward":9.58285,"corporateActions":[]},{"language":"en-US",
        "region":"US","quoteType":"EQUITY","symbol":"7203.T","shortName":"TOYOTA MOTOR CORP","longName":"Toyota \#
        Motor Corporation","currency":"JPY","marketState":"POSTPOST","exchangeTimezoneName":"Asia/Tokyo",
        "priceHint":2,"regularMarketPrice":2893.5,"regularMarketChange":37.0,
        "regularMarketChangePercent":1.2952914,"regularMarketPreviousClose":2856.5,
        "regularMarketOpen":2873.5,"regularMarketDayHigh":2900.0,"regularMarketDayLow":2867.5,
        "regularMarketVolume":23901000,"fiftyTwoWeekHigh":4000.0,"fiftyTwoWeekLow":2686.0,
        "epsForward":324.22,"corporateActions":[]},{"language":"en-US","region":"US",
        "quoteType":"CRYPTOCURRENCY","symbol":"BTC-USD","shortName":"Bitcoin USD","longName":"Bitcoin USD",
        "currency":"USD","marketState":"REGULAR","exchangeTimezoneName":"UTC","priceHint":2,
        "regularMarketPrice":86416.4,"regularMarketChange":1140.0391,"regularMarketChangePercent":1.3368758,
        "regularMarketPreviousClose":86513.38,"regularMarketOpen":86513.38,"regularMarketDayHigh":86929.66,
        "regularMarketDayLow":85443.79,"regularMarketVolume":25379489792,"fiftyTwoWeekHigh":126198.07,
        "fiftyTwoWeekLow":57747.766,"corporateActions":[]}],"error":null}}
        """#.utf8)
}
