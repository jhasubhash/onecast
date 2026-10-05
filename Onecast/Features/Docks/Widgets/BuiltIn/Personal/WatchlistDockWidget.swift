import OnecastPluginKit
import SwiftUI

/// A list of symbols with their prices and moves; compact, it turns through them one at a time.
final class WatchlistDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Watchlist", subtitle: "Prices and moves for a list of symbols",
        icon: "list.bullet.rectangle", category: "Personal", sizes: [.wide, .expanded, .compact])

    static let preferences: [PluginPreference] = [
        PluginPreference(
            name: "symbols", title: "Symbols",
            description:
                "Yahoo Finance symbols separated by commas or spaces. The first \(StockSymbols.watchlistLimit) are used.",
            placeholder: StockSymbols.defaultWatchlist,
            defaultValue: .string(StockSymbols.defaultWatchlist))
    ]

    private let model = WatchlistModel()

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(WatchlistTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(WatchlistPopoverView(model: model, context: context))
    }

    func didRemove() {
        model.didRemove()
    }
}
