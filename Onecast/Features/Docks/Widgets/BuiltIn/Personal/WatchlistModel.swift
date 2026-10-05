import Foundation
import OnecastPluginKit

/// One Watchlist widget's live state: a quote for every symbol, from one batched request.
@MainActor
@Observable
final class WatchlistModel {
    /// A symbol's place in the list: its quote, or why it has none.
    struct Entry: Identifiable {
        let symbol: String
        let quote: StockQuote?
        let failure: StockError?

        var id: String { symbol }
    }

    private(set) var symbols: [String] = []
    private(set) var quotes: [String: StockQuote] = [:]
    private(set) var failures: [String: StockError] = [:]
    /// Why the whole list failed to refresh; the quotes already held stay on show, dimmed.
    private(set) var error: StockError?
    let detail = StockChartModel()
    /// What the popover has picked; falls back to the first symbol when it left the list.
    private var picked: String?

    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var nextFetch: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?

    var entries: [Entry] {
        symbols.map { Entry(symbol: $0, quote: quotes[$0], failure: failures[$0]) }
    }

    var isStale: Bool { error != nil && !quotes.isEmpty }

    var selected: String? {
        picked.flatMap { symbols.contains($0) ? $0 : nil } ?? symbols.first
    }

    func select(_ symbol: String) {
        picked = symbol
    }

    /// Drives the widget while its tile is on screen, and follows edits to its symbols setting.
    func run(preferences: DockWidgetPreferences) async {
        follow(preferences)
        for await _ in PersonalDefaults.changes() {
            follow(preferences)
        }
        stopRefreshing()
    }

    /// The popover's Try again: fetch now, and reload its chart too.
    func retry() {
        nextFetch = nil
        startRefreshing()
        detail.retry()
    }

    func didRemove() {
        stopRefreshing()
    }

    private func follow(_ preferences: DockWidgetPreferences) {
        let wanted = StockSymbols.parse(preferences.string("symbols"))
        if !isConfigured || wanted != symbols {
            isConfigured = true
            symbols = wanted
            quotes = quotes.filter { wanted.contains($0.key) }
            failures = [:]
            nextFetch = nil
            error = wanted.isEmpty ? .noSymbols : nil
        } else if loop != nil {
            return
        }
        startRefreshing()
    }

    private func startRefreshing() {
        loop?.cancel()
        loop = nil
        guard !symbols.isEmpty else { return }
        loop = Task { [weak self] in await self?.refreshLoop() }
    }

    private func stopRefreshing() {
        loop?.cancel()
        loop = nil
    }

    private func refreshLoop() async {
        while !Task.isCancelled, !symbols.isEmpty {
            let wait = StockCadence.delay(nextFetch: nextFetch, now: Date())
            guard wait <= 0 else {
                try? await Task.sleep(for: .seconds(wait))
                continue
            }
            await refresh()
        }
    }

    private func refresh() async {
        let requested = symbols
        do throws(StockError) {
            let batch = try await DockWidgetServices.current.stocks.quotes(symbols: requested)
            guard !Task.isCancelled, requested == symbols else { return }
            quotes = Dictionary(batch.quotes.map { ($0.symbol.uppercased(), $0) }) { _, latest in latest }
            failures = batch.failures
            error = nil
            nextFetch = Date().addingTimeInterval(
                StockCadence.interval(for: batch.quotes.map(\.marketState)))
        } catch {
            guard !Task.isCancelled, requested == symbols else { return }
            self.error = error
            nextFetch = Date().addingTimeInterval(StockCadence.interval(after: error))
        }
    }
}
