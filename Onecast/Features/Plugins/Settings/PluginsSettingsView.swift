import AppKit
import OnecastPluginKit
import SwiftUI

/// Settings › Plugins: the master switch, a row per installed plugin (with the settings its manifest
/// declares), and where they live on disk.
struct PluginsSettingsView: View {
    @Environment(AppCore.self) private var core
    /// The plugin whose settings are open; one at a time, as Settings › Extensions does it.
    @State private var expanded: String?

    var body: some View {
        @Bindable var settings = core.settings
        return Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { settings.pluginsEnabled },
                        set: { core.pluginCoordinator.setPluginsEnabled($0) })
                ) {
                    Text("Enable plugins")
                    Text(
                        "Run native Swift plugins. A plugin is compiled code that runs inside "
                        + "Onecast with full access to this Mac — enable only plugins you trust.")
                }
                Toggle(isOn: $settings.pluginsShowInLauncher) {
                    Text("Show in launcher")
                    Text("List installed plugins in launcher search.")
                }
                .disabled(!settings.pluginsEnabled)
            }

            Section("Installed") {
                if core.plugins.installed.isEmpty {
                    Text("No plugins installed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(core.plugins.installed) { install in
                        PluginRowView(
                            install: install, isExpanded: expanded == install.id,
                            onToggle: { expanded = expanded == install.id ? nil : install.id })
                    }
                }
                Button("Import Plugin…") {
                    core.pluginCoordinator.importPluginFromFolder()
                }
                Button("Reveal Plugins Folder…") {
                    NSWorkspace.shared.activateFileViewerSelecting([PluginCatalog.pluginsDirectory()])
                }
            }
            .settingsEnabled(settings.pluginsEnabled)
        }
        .formStyle(.grouped)
        .releasesFocusOnOutsideClick()
    }
}

/// A plugin's summary row; when its manifest declares preferences, Settings opens them below it.
private struct PluginRowView: View {
    @Environment(AppCore.self) private var core
    let install: PluginInstall
    let isExpanded: Bool
    let onToggle: () -> Void

    private var preferences: [PluginPreference] { install.manifest.preferences ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            summary
            if isExpanded {
                ForEach(preferences, id: \.name) { preference in
                    PluginPreferenceRow(pluginID: install.manifest.identifier, preference: preference)
                }
                .padding(.leading, 20 + Theme.Spacing.sm)
            }
        }
    }

    private var summary: some View {
        HStack {
            Image(systemName: install.manifest.icon ?? "puzzlepiece.extension")
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(install.manifest.name)
                if let subtitle = install.manifest.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !preferences.isEmpty {
                // A real button: in a grouped Form, a tap gesture on the row never receives the click.
                Button(action: onToggle) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Settings")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .accessibilityLabel(
                    isExpanded ? "Hide \(install.manifest.name) settings" : "\(install.manifest.name) settings")
            }
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([install.directory])
            }
            Button("Uninstall", role: .destructive) {
                core.pluginCoordinator.confirmUninstall(install)
            }
        }
    }
}

/// One manifest preference, stored where the plugin reads it through `PluginPreferences`.
private struct PluginPreferenceRow: View {
    let pluginID: String
    let preference: PluginPreference
    @State private var text = ""
    @State private var flag = false

    private var store: PluginPreferences { PluginPreferences(pluginID: pluginID) }

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(preference.title)
            if let description = preference.description {
                Text(description)
            }
        }
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var control: some View {
        switch preference.kind {
        case .checkbox:
            Toggle("", isOn: $flag)
                .labelsHidden()
                .onChange(of: flag) { _, value in
                    if value != store.bool(preference.name) { store.set(value, for: preference.name) }
                }
        case .dropdown:
            Picker("", selection: $text) {
                ForEach(preference.options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .onChange(of: text) { _, value in save(value) }
        case .directory:
            HStack {
                Text(text.isEmpty ? "Not set" : (text as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…", action: chooseDirectory)
            }
        case .textfield:
            TextField("", text: $text, prompt: preference.placeholder.map(Text.init))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(maxWidth: 300)
                .pointerStyle(.horizontalText)
                .onChange(of: text) { _, value in save(value) }
        }
    }

    private func load() {
        text = store.string(preference.name) ?? ""
        flag = store.bool(preference.name)
    }

    /// Empty clears the user's value, so the manifest default applies again; an unchanged value
    /// (the default the pane just loaded) is never written, so a later default still reaches it.
    private func save(_ value: String) {
        guard value != (store.string(preference.name) ?? "") else { return }
        store.set(value.isEmpty ? nil : value, for: preference.name)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if !text.isEmpty { panel.directoryURL = URL(fileURLWithPath: text) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text = url.path
        save(url.path)
    }
}
