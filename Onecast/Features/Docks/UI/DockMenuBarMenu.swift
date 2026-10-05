import SwiftUI

/// The Docks submenu of Onecast's own menu-bar item, so a switch needs no window or palette.
struct DockMenuBarMenu: View {
    var body: some View {
        let switching = AppCore.shared.dockSwitchCoordinator
        // Read through Observation, so an edit in Settings reshapes the menu at once.
        let configuration = AppCore.shared.docks.configuration
        Menu("Docks") {
            if !configuration.setups.isEmpty {
                Section("Setups") {
                    ForEach(configuration.setups) { setup in
                        Toggle(
                            setup.name,
                            isOn: Binding(
                                get: { configuration.activeSetupID == setup.id },
                                set: { _ in switching.switchToSetup(id: setup.id) }))
                    }
                }
            }
            if !configuration.docks.isEmpty {
                Section("Show or Hide") {
                    ForEach(configuration.docks) { dock in
                        Button(dock.launcherTitle) { switching.toggleDock(id: dock.id) }
                    }
                }
            }
            if !configuration.nativeLayouts.isEmpty {
                Menu("Apply macOS Dock Layout") {
                    ForEach(configuration.nativeLayouts) { layout in
                        Toggle(
                            layout.name,
                            isOn: Binding(
                                get: { configuration.activeNativeLayoutID == layout.id },
                                set: { _ in switching.applyNativeLayout(id: layout.id) }))
                    }
                }
            }
            Divider()
            Button("Manage Docks…") { switching.manageDocks() }
        }
    }
}
