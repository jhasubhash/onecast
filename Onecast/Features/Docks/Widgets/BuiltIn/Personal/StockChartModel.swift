import Foundation

/// The chart a popover shows: one symbol over the range the picker is on, kept fresh while open.
@MainActor
@Observable
final class StockChartModel {
    /// What a popover's chart task restarts on: another symbol, another range, or a retry.
    struct Request: Hashable {
        let symbol: String?
        let range: StockRange
        let attempt: Int
    }

    var range: StockRange = .day
    private(set) var data: StockChartData?
    private(set) var error: StockError?
    private(set) var isLoading = false
    private var attempt = 0

    func request(symbol: String?) -> Request {
        Request(symbol: symbol, range: range, attempt: attempt)
    }

    func retry() {
        attempt += 1
    }

    /// Loads the chart, then reloads it at the market's pace until the popover goes away.
    func run(symbol: String, range: StockRange) async {
        if data?.quote.symbol != symbol { data = nil }
        error = nil
        while !Task.isCancelled {
            isLoading = true
            let delay: TimeInterval
            do throws(StockError) {
                let result = try await DockWidgetServices.current.stocks.chart(symbol: symbol, range: range)
                guard !Task.isCancelled else { return }
                data = result
                error = nil
                delay = StockCadence.interval(for: [result.quote.marketState])
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
                delay = StockCadence.interval(after: error)
            }
            isLoading = false
            try? await Task.sleep(for: .seconds(delay))
        }
    }
}
