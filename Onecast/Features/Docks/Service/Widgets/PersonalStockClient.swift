import Foundation

/// Yahoo Finance over HTTP: the keyless chart endpoint and the cookie-and-crumb quote endpoint.
enum StockYahooClient {
    private static let host = "query1.finance.yahoo.com"
    /// Yahoo turns away the default `CFNetwork` agent from some endpoints.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    private static let timeout: TimeInterval = 12
    private static let attempts = 3
    /// A fallback over a long list is the burst Yahoo answers with 429s, so it is paced.
    private static let fallbackWidth = 4
    private static let crumbLimit = 40

    /// Ephemeral, so Yahoo's cookie lives in this session's own jar and nothing reaches disk.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    // MARK: - Calls

    /// The quote and the closes for `symbol` over `range`, from one chart request.
    static func chart(symbol: String, range: StockRange) async throws(StockError) -> StockChartData {
        try await chart(
            symbol: symbol, range: range, rangeParameter: range.rangeParameter,
            intervalParameter: range.intervalParameter)
    }

    /// Everything about a symbol's day, on the lightest chart request Yahoo answers.
    static func snapshot(symbol: String) async throws(StockError) -> StockQuote {
        try await chart(symbol: symbol, range: .day, rangeParameter: "1d", intervalParameter: "1d").quote
    }

    /// Every symbol's quote in one request. Yahoo only answers this with a crumb it issued.
    static func quotes(symbols: [String], crumb: String) async throws(StockError) -> StockBatch {
        let url = try endpoint(
            path: "/v7/finance/quote",
            query: [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "crumb", value: crumb),
            ])
        let data = try await body(of: url, symbol: nil)
        return try StockFeed.batch(from: data, symbols: symbols, now: Date())
    }

    /// Quotes one symbol at a time when the batched request failed, a few at once.
    static func snapshots(symbols: [String]) async -> StockBatch {
        var outcomes: [String: Result<StockQuote, StockError>] = [:]
        await withTaskGroup(of: (String, Result<StockQuote, StockError>).self) { group in
            var pending = symbols[...]
            func next() {
                guard let symbol = pending.popFirst() else { return }
                group.addTask {
                    let outcome = await result { () async throws(StockError) -> StockQuote in
                        try await snapshot(symbol: symbol)
                    }
                    return (symbol, outcome)
                }
            }
            for _ in 0..<fallbackWidth { next() }
            for await (symbol, outcome) in group {
                outcomes[symbol] = outcome
                next()
            }
        }
        var quotes: [StockQuote] = []
        var failures: [String: StockError] = [:]
        for symbol in symbols {
            switch outcomes[symbol] {
            case .success(let quote)?: quotes.append(quote)
            case .failure(let error)?: failures[symbol] = error
            case nil: failures[symbol] = .malformed
            }
        }
        return StockBatch(quotes: quotes, failures: failures, fetchedAt: Date())
    }

    /// Yahoo's session crumb: a cookie from its front door, then the crumb that cookie unlocks.
    static func crumb() async throws(StockError) -> String {
        guard let door = URL(string: "https://fc.yahoo.com") else { throw .malformed }
        // The front door answers 404; only the cookie it sets matters.
        _ = try? await session.data(for: request(door))
        let data = try await body(of: try endpoint(path: "/v1/test/getcrumb", query: []), symbol: nil)
        let crumb = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !crumb.isEmpty, crumb.count < crumbLimit, !crumb.lowercased().contains("too many") else {
            throw .unauthorized
        }
        return crumb
    }

    /// Runs `work` and hands back its outcome as a value, so a task can return a typed failure.
    static func result<Value: Sendable>(
        of work: @Sendable () async throws(StockError) -> Value
    ) async -> Result<Value, StockError> {
        do throws(StockError) {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Requests

    private static func chart(
        symbol: String, range: StockRange, rangeParameter: String, intervalParameter: String
    ) async throws(StockError) -> StockChartData {
        let url = try endpoint(
            path: "/v8/finance/chart/\(symbol)",
            query: [
                URLQueryItem(name: "interval", value: intervalParameter),
                URLQueryItem(name: "range", value: rangeParameter),
            ])
        let data = try await body(of: url, symbol: symbol)
        return try StockFeed.chart(from: data, symbol: symbol, range: range, now: Date())
    }

    private static func endpoint(path: String, query: [URLQueryItem]) throws(StockError) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw .malformed }
        return url
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private enum Attempt {
        case data(Data)
        case retry(StockError)
        case fail(StockError)
    }

    /// The body of a 200 answer; a 429 or 5xx backs off and retries.
    private static func body(of url: URL, symbol: String?) async throws(StockError) -> Data {
        var last = StockError.malformed
        for attempt in 0..<attempts {
            if attempt > 0 {
                let backoff = 200 << (attempt - 1) + Int.random(in: 0...120)
                try? await Task.sleep(for: .milliseconds(backoff))
            }
            switch await once(url, symbol: symbol) {
            case .data(let data): return data
            case .fail(let error): throw error
            case .retry(let error): last = error
            }
        }
        throw last
    }

    private static func once(_ url: URL, symbol: String?) async -> Attempt {
        do {
            let (data, response) = try await session.data(for: request(url))
            guard let http = response as? HTTPURLResponse else { return .fail(.malformed) }
            if http.statusCode == 200 { return .data(data) }
            let error = StockFeed.error(status: http.statusCode, body: data, symbol: symbol)
            return http.statusCode == 429 || http.statusCode >= 500 ? .retry(error) : .fail(error)
        } catch let error as URLError {
            let mapped = stockError(for: error)
            return error.code == .timedOut || error.code == .networkConnectionLost
                ? .retry(mapped) : .fail(mapped)
        } catch {
            return .fail(.network(error.localizedDescription))
        }
    }

    private static func stockError(for error: URLError) -> StockError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
            .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost:
            .offline
        case .timedOut:
            .timedOut
        default:
            .network(error.localizedDescription)
        }
    }
}
