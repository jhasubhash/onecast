import SwiftUI

struct NotesSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.notesEnabled) {
                    SettingsRowTitle(.notesNotes, "Enable Notes")
                    Text("Keep plain Markdown notes in a floating editor, loaded only when needed.")
                }
                LabeledContent {
                    if settings.notesFolder != nil {
                        Button("Use Default", action: core.notesCoordinator.resetNotesFolder)
                    }
                    Button("Choose…", action: core.notesCoordinator.chooseNotesFolder)
                } label: {
                    SettingsRowTitle(.notesNotes, "Notes Folder")
                    Text((core.notesStore.notesDirectory.path as NSString).abbreviatingWithTildeInPath)
                }
            } header: {
                SettingsSectionHeader(.notesNotes)
            }

            FeatureCommandsSection(owner: .notes, anchor: .notesCommands)
                .settingsEnabled(settings.notesEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notes)
    }
}
