import AppKit
import SwiftUI

/// Settings › Docks: the master switch, then one dock's editor at a time, then everything shared.
struct DocksSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DockStore.self) private var store
    @State private var editedDockID: UUID?
    @State private var editedLayoutID: UUID?
    @State private var displays = DockDisplays.connected()

    /// A dock removed under the editor leaves the first one in its place.
    private var editedDock: CustomDock? {
        editedDockID.flatMap { store.dock(id: $0) } ?? store.docks.first
    }

    var body: some View {
        Form {
            DocksSwitchSection()

            Group {
                FeatureCommandsSection(owner: .docks, anchor: .docksCommands)
                CustomDocksSection(displays: displays, editedDockID: editedDock?.id) { id in
                    editedDockID = id
                    editedLayoutID = nil
                }
                if let dock = editedDock {
                    let layout = dock.layouts.first { $0.id == editedLayoutID } ?? dock.activeLayout
                    DockPlacementSection(dockID: dock.id, displays: displays)
                    DockAppearanceSection(dockID: dock.id)
                    DockContentSection(dockID: dock.id)
                    DockLayoutsSection(dockID: dock.id, editedLayoutID: layout.id) {
                        editedLayoutID = $0
                    }
                    DockItemsSection(dockID: dock.id, layoutID: layout.id)
                }
                NativeDockLayoutsSection()
                DockSetupsSection()
                DockWidgetsSettingsSection()
            }
            .settingsEnabled(settings.docksEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.docks)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            displays = DockDisplays.connected()
        }
    }
}

/// The feature's master switch and how the custom docks share the screen with the macOS Dock.
struct DocksSwitchSection: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(DockStore.self) private var store

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        let configuration = store.configuration
        Section {
            Toggle(
                isOn: Binding(
                    get: { settings.docksEnabled },
                    set: { coordinator.setDocksEnabled($0) })
            ) {
                SettingsRowTitle(.docksDocks, "Enable Docks")
                Text("Docks on any screen edge, each with its own apps, folders, links and widgets.")
            }

            Group {
                Picker(
                    selection: Binding(
                        get: { configuration.nativeMode },
                        set: { coordinator.setNativeMode($0) })
                ) {
                    ForEach(NativeDockMode.allCases, id: \.self) { mode in
                        Text(mode.settingsTitle).tag(mode)
                    }
                } label: {
                    SettingsRowTitle(.docksDocks, "Dock setup")
                    Text(configuration.nativeMode.settingsDetail)
                }

                if configuration.nativeMode == .customMain {
                    Picker(
                        selection: Binding(
                            get: { configuration.nativeHiding },
                            set: { coordinator.setNativeHiding($0) })
                    ) {
                        ForEach(NativeDockHiding.allCases, id: \.self) { hiding in
                            Text(hiding.settingsTitle).tag(hiding)
                        }
                    } label: {
                        Text("macOS Dock")
                        Text(configuration.nativeHiding.settingsDetail)
                    }
                }
            }
            .settingsEnabled(settings.docksEnabled)
        } header: {
            SettingsSectionHeader(.docksDocks)
        } footer: {
            Text("Onecast puts the macOS Dock back when Docks is turned off, on quit and after a crash.")
        }
    }
}
