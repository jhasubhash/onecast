import OnecastPluginKit
import SwiftUI

/// One row per preference a widget declares, under `dockwidget.<instance>.<name>`. Needs `AppCore`.
struct DockWidgetPreferencesEditor: View {
    @Environment(AppCore.self) private var core
    let instanceID: UUID
    let widgetID: String

    var body: some View {
        rows(in: core.dockCoordinator.widgets)
    }

    private func rows(in widgets: DockWidgetManager) -> some View {
        // Defaults first: each row reads its stored value the moment it appears.
        widgets.registerDefaults(for: instanceID, widgetID: widgetID)
        let preferences = widgets.descriptor(id: widgetID)?.preferences ?? []
        return ForEach(preferences, id: \.name) { preference in
            PreferenceRow(
                preference: preference,
                key: { DockWidgetPreferences.key(instanceID: instanceID.uuidString, name: $0) },
                onChange: { widgets.preferencesDidChange() }
            )
            // Per-instance identity, so a row never carries one instance's text into another.
            .id("\(instanceID)-\(preference.name)")
        }
    }
}
