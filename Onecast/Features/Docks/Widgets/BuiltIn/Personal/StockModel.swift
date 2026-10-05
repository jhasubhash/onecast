import Foundation
import OnecastPluginKit

/// One Stock widget's live state: its symbol's day, refreshed while its tile is on screen.
@MainActor
@Observable
final class StockModel {
    private(set) var symbol: String?
    /// The latest good one-day chart; kept, and dimmed, when a later fetch fails.
    private(set) var chart: StockChartData?
    private(set) var error: StockError?
    let detail = StockChartModel()

    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var nextFetch: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?

    var quote: StockQuote? { chart?.quote }
    var isStale: Bool { error != nil && chart != nil }

    /// Drives the widget while its tile is on screen, and follows edits to its symbol setting.
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
        let wanted = StockSymbols.single(preferences.string("symbol"))
        if !isConfigured || wanted != symbol {
            isConfigured = true
            symbol = wanted
            chart = nil
            nextFetch = nil
            error = wanted == nil ? .noSymbols : nil
        } else if loop != nil {
            return
        }
        startRefreshing()
    }

    private func startRefreshing() {
        loop?.cancel()
        loop = nil
        guard symbol != nil else { return }
        loop = Task { [weak self] in await self?.refreshLoop() }
    }

    private func stopRefreshing() {
        loop?.cancel()
        loop = nil
    }

    private func refreshLoop() async {
        while !Task.isCancelled, symbol != nil {
            let wait = StockCadence.delay(nextFetch: nextFetch, now: Date())
            guard wait <= 0 else {
                try? await Task.sleep(for: .seconds(wait))
                continue
            }
            await refresh()
        }
    }

    private func refresh() async {
        guard let requested = symbol else { return }
        do throws(StockError) {
            let result = try await DockWidgetServices.current.stocks.chart(symbol: requested, range: .day)
            guard !Task.isCancelled, requested == symbol else { return }
            chart = result
            error = nil
            nextFetch = Date().addingTimeInterval(
                StockCadence.interval(for: [result.quote.marketState]))
        } catch {
            guard !Task.isCancelled, requested == symbol else { return }
            self.error = error
            nextFetch = Date().addingTimeInterval(StockCadence.interval(after: error))
        }
    }
}
