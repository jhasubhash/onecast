import OnecastPluginKit
import SwiftUI

/// The popover a Watchlist click opens: every symbol's quote, and a chart for the one picked.
struct WatchlistPopoverView: View {
    let model: WatchlistModel
    let context: DockWidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if let error = model.error ?? model.detail.error {
                StockFailureView(error: error, context: context, retry: model.retry)
            }
            if !model.symbols.isEmpty {
                list
            }
            if let selected = model.selected {
                StockChartSectionView(
                    chart: model.detail, symbol: selected, quote: model.quotes[selected])
            }
        }
        .padding(PersonalPopover.padding)
        .frame(width: PersonalPopover.width)
    }

    private var list: some View {
        let rows = CGFloat(model.symbols.count)
        let height = min(
            rows * WatchlistPopoverRow.height + (rows - 1) * Theme.Spacing.xxs,
            PersonalPopover.listMaxHeight)
        return ScrollView {
            VStack(spacing: Theme.Spacing.xxs) {
                ForEach(model.entries) { entry in
                    WatchlistPopoverRow(entry: entry, isSelected: entry.symbol == model.selected) {
                        model.select(entry.symbol)
                    }
                }
            }
        }
        .overflowFade()
        .thinScrollbar()
        .frame(height: height)
    }
}
