import Foundation

/// Where stock widgets get quotes: identical requests in flight, and the crumb, are shared.
@MainActor
final class StockQuoteProvider {
    private struct ChartKey: Hashable {
        let symbol: String
        let range: StockRange
    }

    /// Held here, not in an actor: the fetchers are `nonisolated` and are handed it by value.
    private var crumb: String?
    private var crumbFlight: Task<Result<String, StockError>, Never>?
    private var chartFlights: [ChartKey: Task<Result<StockChartData, StockError>, Never>] = [:]
    private var batchFlights: [[String]: Task<Result<StockBatch, StockError>, Never>] = [:]

    init() {}

    /// The quote and closes for `symbol` over `range`.
    func chart(symbol: String, range: StockRange) async throws(StockError) -> StockChartData {
        let key = ChartKey(symbol: symbol, range: range)
        let flight = chartFlights[key] ?? startChartFlight(key)
        return try await flight.value.get()
    }

    /// One batched request, or one each if Yahoo refuses it; throws only if no symbol got a quote.
    func quotes(symbols: [String]) async throws(StockError) -> StockBatch {
        guard !symbols.isEmpty else { throw .noSymbols }
        let flight = batchFlights[symbols] ?? startBatchFlight(symbols)
        return try await flight.value.get()
    }

    // MARK: - Flights

    private func startChartFlight(_ key: ChartKey) -> Task<Result<StockChartData, StockError>, Never> {
        let flight = Task { [unowned self] in
            let result = await StockYahooClient.result { @Sendable () async throws(StockError) -> StockChartData in
                try await StockYahooClient.chart(symbol: key.symbol, range: key.range)
            }
            chartFlights[key] = nil
            return result
        }
        chartFlights[key] = flight
        return flight
    }

    private func startBatchFlight(_ symbols: [String]) -> Task<Result<StockBatch, StockError>, Never> {
        let flight = Task { [unowned self] in
            let result = await fetchBatch(symbols)
            batchFlights[symbols] = nil
            return result
        }
        batchFlights[symbols] = flight
        return flight
    }

    private func startCrumbFlight() -> Task<Result<String, StockError>, Never> {
        let flight = Task { [unowned self] in
            let result = await StockYahooClient.result { @Sendable () async throws(StockError) -> String in
                try await StockYahooClient.crumb()
            }
            if case .success(let value) = result { crumb = value }
            crumbFlight = nil
            return result
        }
        crumbFlight = flight
        return flight
    }

    // MARK: - Batch

    private func currentCrumb() async throws(StockError) -> String {
        if let crumb { return crumb }
        let flight = crumbFlight ?? startCrumbFlight()
        return try await flight.value.get()
    }

    private func fetchBatch(_ symbols: [String]) async -> Result<StockBatch, StockError> {
        do throws(StockError) {
            let crumb = try await currentCrumb()
            let batch = try await StockYahooClient.quotes(symbols: symbols, crumb: crumb)
            return Self.resolved(batch, symbols: symbols)
        } catch {
            if error.invalidatesCrumb { crumb = nil }
            return Self.resolved(await StockYahooClient.snapshots(symbols: symbols), symbols: symbols)
        }
    }

    /// A batch with at least one quote stands; one with none is the failure of its first symbol.
    private static func resolved(_ batch: StockBatch, symbols: [String]) -> Result<StockBatch, StockError> {
        guard batch.quotes.isEmpty else { return .success(batch) }
        return .failure(symbols.lazy.compactMap { batch.failures[$0] }.first ?? .malformed)
    }
}
