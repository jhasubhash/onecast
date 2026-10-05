import OnecastPluginKit

/// A first-party DockWidget: compiled into Onecast, built through the same protocol a third-party
/// widget implements, so the dock hosts both one way.
@MainActor
struct BuiltInDockWidget: Identifiable {
    /// `builtin.<name>`; stored in `DockWidgetReference.widgetID`.
    let id: String
    let metadata: DockWidgetMetadata
    /// The per-instance settings, edited in the dock editor and read via `DockWidgetPreferences`.
    let preferences: [PluginPreference]
    let make: @MainActor () -> any OnecastDockWidget

    init<Widget: OnecastDockWidget>(
        _ name: String, _ type: Widget.Type, preferences: [PluginPreference] = []
    ) {
        id = "builtin.\(name)"
        metadata = Widget.metadata
        self.preferences = preferences
        make = { Widget() }
    }
}

/// Every built-in widget, in library order. Each group lives in its own file under `BuiltIn/`.
@MainActor
enum BuiltInDockWidgets {
    static var all: [BuiltInDockWidget] { time + productivity + system + personal }

    static func widget(id: String) -> BuiltInDockWidget? {
        all.first { $0.id == id }
    }
}
