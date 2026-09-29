import SwiftUI

/// One installed tool's own settings: which of its models the pickers list, and how it is launched.
struct AIProviderConfigureSheet: View {
    struct Model: Identifiable {
        let id: String
        let name: String
    }

    private enum Page: String, CaseIterable, Identifiable {
        case models = "Models"
        case advanced = "Advanced"
        var id: Self { self }
    }

    let kind: InstalledAIKind
    let models: [Model]
    /// Where the automatic lookup found the command, shown so a set path can be compared with it.
    let foundCommand: URL?
    let onClose: () -> Void

    @Environment(AISettingsStore.self) private var settings
    @State private var page = Page.models
    @State private var query = ""
    @State private var commandPath = ""
    @State private var environmentText = ""
    @State private var environmentError: String?
    /// A read that failed leaves the variables alone, so a save never writes blanks over them.
    @State private var environmentReadable = true

    private var source: AIModelSource { kind.source }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(kind.title).font(.title2.weight(.bold))
                Picker("Page", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.md)

            switch page {
            case .models: modelsPage
            case .advanced: advancedPage
            }

            Divider()
            HStack(spacing: Theme.Spacing.lg) {
                if let environmentError {
                    Label(environmentError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(width: Theme.Size.editorSheetWidth, height: 600)
        .onAppear(perform: load)
    }

    // MARK: - Models

    private var modelsPage: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if models.isEmpty {
                Text("\(kind.title) has listed no models yet. Check it in AI Providers, then come back.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xxl)
                Spacer()
            } else {
                HStack(spacing: Theme.Spacing.md) {
                    TextField("Filter models", text: $query, prompt: Text("Filter models"))
                        .textFieldStyle(.roundedBorder)
                    Button("Show All") { settings.showAllModels(in: source) }
                    Button("Hide All") { settings.hideAllModels(in: source) }
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                Text("\(shownCount) of \(models.count) listed in model pickers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xxl)
                // A List builds only the rows on screen; OpenCode alone offers hundreds.
                List(filteredModels) { model in
                    modelRow(model)
                }
                .listStyle(.inset)
            }
        }
    }

    private func modelRow(_ model: Model) -> some View {
        let isDefault = settings.defaultModel?.source == source && settings.defaultModel?.model == model.id
        return Toggle(isOn: shownBinding(model.id)) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(model.name)
                if model.name != model.id {
                    Text(model.id).font(.caption).foregroundStyle(.secondary)
                }
                if isDefault {
                    Text("Default").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isDefault)
        .help(isDefault ? "The default model is always listed." : "")
    }

    private var filteredModels: [Model] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return models }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var shownCount: Int {
        models.count { settings.isModelShown($0.id, in: source) }
    }

    private func shownBinding(_ model: String) -> Binding<Bool> {
        Binding(
            get: { settings.isModelShown(model, in: source) },
            set: { settings.setModel(model, shown: $0, in: source, available: models.map(\.id)) })
    }

    // MARK: - Advanced

    private var advancedPage: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.md) {
                        TextField("Command path", text: $commandPath, prompt: Text("Automatic"))
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                        Button("Choose…", action: chooseCommand)
                    }
                } label: {
                    Text("Command path")
                }
                if let commandNote {
                    Text(commandNote.text)
                        .font(.caption)
                        .foregroundStyle(commandNote.isProblem ? .orange : .secondary)
                }
            } header: {
                Text("Command")
            } footer: {
                Text(
                    "Leave it empty to find \(kind.command) the way Terminal does. A path set here "
                        + "is used as is: if nothing can run there, \(kind.title) stays unavailable."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $environmentText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 120)
                    .padding(Theme.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if environmentText.isEmpty {
                            Text(verbatim: "HTTPS_PROXY=http://127.0.0.1:8080")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(Theme.Spacing.sm)
                                .allowsHitTesting(false)
                        }
                    }
                    .disabled(!environmentReadable)
                ForEach(ignoredVariables, id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Environment")
            } footer: {
                Text(
                    "One NAME=value per line, set each time \(kind.title) starts. Values are kept "
                        + "in your login Keychain and never travel in a backup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var commandNote: (text: String, isProblem: Bool)? {
        let launch = InstalledAILaunch(commandPath: commandPath)
        switch launch.command() {
        case .automatic:
            return foundCommand.map { ("Found at \($0.path)", false) }
        case .executable:
            return nil
        case .missing(let path):
            return (InstalledAILaunch.missingCommandMessage(path), true)
        }
    }

    private var ignoredVariables: [String] {
        AssistantSecretStore.parse(environmentText).keys.sorted().compactMap { name in
            if !InstalledAILaunch.isVariableName(name) {
                return "“\(name)” isn’t a variable name, so it is not set."
            }
            if kind.isManagedVariable(name) {
                return "Onecast sets \(name) itself, so this value is not used."
            }
            return nil
        }
    }

    private func chooseCommand() {
        let start =
            InstalledAILaunch(commandPath: commandPath).command()
            .executableDirectory
            ?? foundCommand?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
        guard
            let url = ExecutablePicker.choose(
                message: "Choose the \(kind.command) command Onecast should run.",
                startingAt: start)
        else { return }
        commandPath = (url.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Load and save

    private func load() {
        commandPath = settings.override(for: kind).commandPath
        do {
            let variables = try settings.environment(for: kind)
            environmentText = AssistantSecretStore.format(
                Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.value) }))
        } catch {
            environmentReadable = false
            environmentError = "The variables could not be read from the Keychain."
        }
    }

    private func done() {
        settings.setCommandPath(commandPath, for: kind)
        if environmentReadable {
            let variables = AssistantSecretStore.parse(environmentText)
                .sorted { $0.key < $1.key }
                .map { InstalledAIVariable(name: $0.key, value: $0.value) }
            do {
                try settings.setEnvironment(variables, for: kind)
            } catch {
                environmentError = "The variables could not be saved to the Keychain."
                return
            }
        }
        onClose()
    }
}

extension InstalledAILaunch.Command {
    /// The folder a set path points into, so the picker opens beside the command it names.
    fileprivate var executableDirectory: URL? {
        guard case .executable(let url) = self else { return nil }
        return url.deletingLastPathComponent()
    }
}
