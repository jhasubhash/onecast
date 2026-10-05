import OnecastPluginKit
import SwiftUI

/// One symbol's live quote, with today's chart and a popover for the longer ranges.
final class StockDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Stock", subtitle: "A live quote and today's chart", icon: "chart.line.uptrend.xyaxis",
        category: "Personal", sizes: [.compact, .wide, .expanded])

    static let preferences: [PluginPreference] = [
        PluginPreference(
            name: "symbol", title: "Symbol",
            description: "A Yahoo Finance symbol, such as AAPL, BRK-B, ^GSPC, EURUSD=X or BTC-USD.",
            placeholder: StockSymbols.defaultSymbol, defaultValue: .string(StockSymbols.defaultSymbol))
    ]

    private let model = StockModel()

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(StockTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(StockPopoverView(model: model, context: context))
    }

    func didRemove() {
        model.didRemove()
    }
}
