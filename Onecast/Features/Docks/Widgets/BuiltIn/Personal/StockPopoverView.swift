import OnecastPluginKit
import SwiftUI

/// The popover a Stock tile click opens: the quote, a chart over a range of the reader's choice.
struct StockPopoverView: View {
    let model: StockModel
    let context: DockWidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if let error = model.detail.error ?? model.error {
                StockFailureView(error: error, context: context, retry: model.retry)
            }
            StockQuoteHeaderView(symbol: model.symbol, quote: model.quote)
            if model.symbol != nil {
                StockChartSectionView(chart: model.detail, symbol: model.symbol, quote: model.quote)
            }
        }
        .padding(PersonalPopover.padding)
        .frame(width: PersonalPopover.width)
    }
}
