import OnecastPluginKit

/// The names a Productivity widget stores its settings under, for its preferences and its views.
enum ProductivityPreferenceName {
    static let layout = "layout"
    static let includeAllDay = "includeAllDay"
    static let showCallButton = "showCallButton"
    static let list = "list"
    static let mode = "mode"
    static let color = "color"
    static let texture = "texture"
    static let ink = "ink"
    static let text = "text"
    static let shortcut = "shortcut"
}

extension BuiltInDockWidgets {
    static let productivity: [BuiltInDockWidget] = [
        BuiltInDockWidget(
            "calendar", CalendarDockWidget.self, preferences: ProductivityPreferences.calendar),
        BuiltInDockWidget(
            "reminders", RemindersDockWidget.self, preferences: ProductivityPreferences.reminders),
        BuiltInDockWidget(
            "stickyNote", StickyNoteDockWidget.self, preferences: ProductivityPreferences.stickyNote),
        BuiltInDockWidget(
            "shortcut", ShortcutDockWidget.self, preferences: ProductivityPreferences.shortcut),
        BuiltInDockWidget("airDrop", AirDropDockWidget.self),
        BuiltInDockWidget("presentation", PresentationDockWidget.self),
    ]
}

private enum ProductivityPreferences {
    static let calendar: [PluginPreference] = [
        PluginPreference(
            name: ProductivityPreferenceName.layout, title: "Layout",
            description: "What the tile shows. A compact tile fits the date and one line.",
            kind: .dropdown,
            options: DockCalendarPlan.Layout.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(DockCalendarPlan.Layout.date.rawValue)),
        PluginPreference(
            name: ProductivityPreferenceName.includeAllDay, title: "Include all-day events",
            kind: .checkbox, defaultValue: .bool(true)),
        PluginPreference(
            name: ProductivityPreferenceName.showCallButton, title: "Show call button",
            description: "A join button on an event that carries a meeting link.",
            kind: .checkbox, defaultValue: .bool(true)),
    ]

    static let reminders: [PluginPreference] = [
        PluginPreference(
            name: ProductivityPreferenceName.list, title: "List",
            description: "The Reminders list to show and add to. Leave empty for all lists.",
            placeholder: "All lists"),
        PluginPreference(
            name: ProductivityPreferenceName.mode, title: "Tile shows",
            kind: .dropdown,
            options: DockReminderPlan.Mode.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(DockReminderPlan.Mode.list.rawValue)),
    ]

    static let stickyNote: [PluginPreference] = [
        PluginPreference(
            name: ProductivityPreferenceName.color, title: "Paper color",
            kind: .dropdown,
            options: StickyPaperColor.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(StickyPaperColor.yellow.rawValue)),
        PluginPreference(
            name: ProductivityPreferenceName.texture, title: "Paper texture",
            kind: .dropdown,
            options: StickyPaperTexture.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(StickyPaperTexture.plain.rawValue)),
        PluginPreference(
            name: ProductivityPreferenceName.ink, title: "Text color",
            kind: .dropdown,
            options: StickyInkColor.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(StickyInkColor.automatic.rawValue)),
    ]

    static let shortcut: [PluginPreference] = [
        PluginPreference(
            name: ProductivityPreferenceName.shortcut, title: "Shortcut",
            description: "The exact name in the Shortcuts app. Hold ⌥ and click the tile to pick one.",
            placeholder: "Shortcut name")
    ]
}
