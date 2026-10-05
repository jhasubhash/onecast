import OnecastPluginKit

extension BuiltInDockWidgets {
    static let time: [BuiltInDockWidget] = [
        BuiltInDockWidget("clock", ClockDockWidget.self, preferences: ClockDockWidget.preferences),
        BuiltInDockWidget(
            "worldClock", WorldClockDockWidget.self, preferences: WorldClockDockWidget.preferences),
        BuiltInDockWidget(
            "focusTimer", FocusTimerDockWidget.self, preferences: FocusTimerDockWidget.preferences),
        BuiltInDockWidget(
            "stopwatch", StopwatchDockWidget.self, preferences: StopwatchDockWidget.preferences),
        BuiltInDockWidget(
            "countdown", CountdownDockWidget.self, preferences: CountdownDockWidget.preferences),
        BuiltInDockWidget("alarm", AlarmDockWidget.self, preferences: AlarmDockWidget.preferences),
        BuiltInDockWidget(
            "timeProgress", TimeProgressDockWidget.self,
            preferences: TimeProgressDockWidget.preferences)
    ]
}
