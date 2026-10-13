import SwiftUI

/// Both flavours in one pane: the built-ins, then the user's own shell commands.
struct CommandsSettingsView: View {
    @Environment(CustomCommandStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherItemsSection(
                kind: .command,
                anchor: .commandsCommands,
                searchPrompt: "Search commands…")

            FeatureSwitchSection(
                anchor: .commandsCustomCommands,
                enableTitle: "Enable custom commands",
                enableSubtitle:
                    "Commands run with your user account in /bin/zsh, or the interpreter a #! line "
                    + "names, so use full executable paths.",
                launcherSubtitle: "Find your commands in launcher search.",
                isEnabled: $settings.customCommandsEnabled,
                showsInLauncher: $settings.customCommandsShowInLauncher)

            Section {
                ForEach(CommandCatalog.entries(ownedBy: .commands)) { entry in
                    FeatureCommandRow(entry: entry)
                }
                if store.commands.isEmpty {
                    Text("Add one to make it searchable from the launcher.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedCommands) { command in
                        CustomCommandSettingsRow(
                            command: command,
                            showsInLauncher: settings.customCommandsShowInLauncher,
                            isEnabled: Binding(
                                get: { command.isEnabled },
                                set: {
                                    core.customCommandCoordinator.setCustomCommandEnabled(
                                        $0, id: command.id)
                                }),
                            onEdit: { core.customCommandCoordinator.editCustomCommand(command) },
                            onDelete: {
                                Task {
                                    await core.customCommandCoordinator.deleteCustomCommand(
                                        id: command.id)
                                }
                            })
                    }
                }
                Button {
                    core.customCommandCoordinator.editCustomCommand(nil)
                } label: {
                    SettingsRowTitle(.commandsCustomCommands, "Add Custom Command")
                }
                Button {
                    Task { await core.customCommandCoordinator.importScriptDirectory() }
                } label: {
                    SettingsRowTitle(.commandsCustomCommands, "Import Raycast Scripts")
                }
            } footer: {
                Text(
                    "Name it, then add an alias or a shortcut if you want one. Importing reads a folder of "
                        + "Raycast script commands, one command per script."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.customCommandsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commands)
        .releasesFocusOnOutsideClick()
    }

    private var sortedCommands: [CustomCommand] {
        store.commands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct CustomCommandSettingsRow: View {
    let command: CustomCommand
    let showsInLauncher: Bool
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: command.name, subtitle: command.command) {
            Image(systemName: command.symbol)
        } trailing: {
            if !command.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .help("Hidden from root search")
            }

            // An alias only reaches the ranker through the launcher slice, so it dims with it.
            AliasField(key: command.entryID, name: command.name)
                .settingsEnabled(command.isEnabled && showsInLauncher && command.showsInRootSearch)

            // A disabled command's shortcut fires into the funnel's refusal, so it dims too.
            ShortcutRecorder(action: .customCommand(id: command.id))
                .settingsEnabled(command.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Custom Command")
            .accessibilityLabel("Edit \(command.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Custom Command")
            .accessibilityLabel("Delete \(command.name)")

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Enabled")
                .accessibilityLabel("Enable \(command.name)")
        }
    }
}
