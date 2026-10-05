import AppKit
import SwiftUI

/// A declared preference as a settings row; `key` says where its value lives, so plugins share it.
struct PreferenceRow: View {
    let preference: PluginPreference
    /// The defaults key a preference name is stored under.
    let key: (String) -> String
    /// Fired after every write, for a surface that must re-read what the value drives.
    var onChange: (() -> Void)?
    @State private var text = ""
    @State private var flag = false

    private var defaults: UserDefaults { .standard }

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
                    guard value != storedFlag else { return }
                    defaults.set(value, forKey: key(preference.name))
                    onChange?()
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

    private var storedText: String {
        defaults.string(forKey: key(preference.name)) ?? ""
    }

    private var storedFlag: Bool {
        defaults.bool(forKey: key(preference.name))
    }

    private func load() {
        text = storedText
        flag = storedFlag
    }

    /// Empty clears the value so the default returns; an unchanged value is never written.
    private func save(_ value: String) {
        guard value != storedText else { return }
        defaults.set(value.isEmpty ? nil : value, forKey: key(preference.name))
        onChange?()
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
