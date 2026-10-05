import OnecastPluginKit
import SwiftUI

/// Water reminders with a daily goal and a day-by-day drink history.
final class HydrationDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Hydration", subtitle: "Water reminders and daily progress", icon: "drop.fill",
        category: "Personal", sizes: [.compact, .wide, .expanded])

    static let preferences: [PluginPreference] = [
        PluginPreference(
            name: "reminderMinutes", title: "Remind me every (minutes)",
            description: "Leave empty or 0 to turn reminders off.", placeholder: "60",
            defaultValue: .string(String(HydrationSettings.defaultReminderMinutes))),
        PluginPreference(
            name: "saveHistory", title: "Save drink history",
            description: "Keeps your drinks in a file so the history survives a relaunch.",
            kind: .checkbox, defaultValue: .bool(true)),
        PluginPreference(
            name: "trackAmounts", title: "Track drink amounts",
            description: "Off counts drinks instead of measuring them.", kind: .checkbox,
            defaultValue: .bool(true)),
        PluginPreference(
            name: "drinkSize", title: "Drink size (mL)", placeholder: "250",
            defaultValue: .string(String(HydrationSettings.defaultDrinkMilliliters))),
        PluginPreference(
            name: "dailyGoal", title: "Daily goal (mL)", placeholder: "2000",
            defaultValue: .string(String(HydrationSettings.defaultGoalMilliliters))),
        PluginPreference(
            name: "dailyGoalDrinks", title: "Daily goal (drinks)",
            description: "Used when drink amounts are not tracked.", placeholder: "8",
            defaultValue: .string(String(HydrationSettings.defaultGoalDrinks))),
    ]

    private let model = HydrationModel()

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(HydrationTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(HydrationPopoverView(model: model))
    }

    func didRemove() {
        model.didRemove()
    }
}
