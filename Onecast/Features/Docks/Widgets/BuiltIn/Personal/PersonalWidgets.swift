import OnecastPluginKit

extension BuiltInDockWidgets {
    /// Hydration, Weather, AI Usage, Stock and Watchlist.
    static let personal: [BuiltInDockWidget] = [
        BuiltInDockWidget(
            "hydration", HydrationDockWidget.self, preferences: HydrationDockWidget.preferences),
        BuiltInDockWidget(
            "weather", WeatherDockWidget.self, preferences: WeatherDockWidget.preferences),
        BuiltInDockWidget(
            "aiUsage", AIUsageDockWidget.self, preferences: AIUsageDockWidget.preferences),
        BuiltInDockWidget(
            "watchlist", WatchlistDockWidget.self, preferences: WatchlistDockWidget.preferences),
        BuiltInDockWidget("stock", StockDockWidget.self, preferences: StockDockWidget.preferences),
    ]
}
