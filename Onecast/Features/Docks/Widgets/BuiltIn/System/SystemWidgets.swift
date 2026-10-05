import OnecastPluginKit

extension BuiltInDockWidgets {
    static let system: [BuiltInDockWidget] = [
        BuiltInDockWidget("nowPlaying", NowPlayingWidget.self, preferences: NowPlayingWidget.preferences),
        BuiltInDockWidget("battery", BatteryWidget.self),
        BuiltInDockWidget(
            "systemActivity", SystemActivityWidget.self, preferences: SystemActivityWidget.preferences),
        BuiltInDockWidget(
            "networkActivity", NetworkActivityWidget.self,
            preferences: NetworkActivityWidget.preferences),
    ]
}
