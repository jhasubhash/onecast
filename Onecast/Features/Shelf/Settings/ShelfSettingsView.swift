import SwiftUI

struct ShelfSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.shelfEnabled) {
                    SettingsRowTitle(.shelfShelf, "Enable Shelf")
                    Text(
                        "Hold files, images, links and text in a floating shelf while you move between apps.")
                }
                Toggle(isOn: $settings.shelfShakeToOpen) {
                    SettingsRowTitle(.shelfShelf, "Shake to Open")
                    Text("Shake the pointer from side to side while dragging to open the shelf under it.")
                }
                .settingsEnabled(settings.shelfEnabled)
            } header: {
                SettingsSectionHeader(.shelfShelf)
            }

            FeatureCommandsSection(owner: .shelf, anchor: .shelfCommands)
                .settingsEnabled(settings.shelfEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.shelf)
    }
}
