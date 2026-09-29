import SwiftUI

/// A provider's model list as checkboxes: which of its models the model pickers list.
struct AIProviderModelsPage: View {
    struct Model: Identifiable {
        let id: String
        let name: String
    }

    let source: AIModelSource
    let models: [Model]
    /// Why the list is empty, when it is: a tool that is off or not ready has nothing to list yet.
    let emptyNote: String

    @Environment(AISettingsStore.self) private var settings
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if models.isEmpty {
                Text(emptyNote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.xl)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: Theme.Spacing.md) {
                    TextField("Filter models", text: $query, prompt: Text("Filter models"))
                        .textFieldStyle(.roundedBorder)
                    Button("Show All") { settings.showAllModels(in: source) }
                    Button("Hide All") { settings.hideAllModels(in: source) }
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.xl)
                Text("\(shownCount) of \(models.count) listed in model pickers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xxl)
                // A List builds only the rows on screen; OpenCode alone offers hundreds.
                List(filteredModels) { model in
                    row(model)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func row(_ model: Model) -> some View {
        let isDefault =
            settings.defaultModel?.source == source && settings.defaultModel?.model == model.id
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
}

/// An installed tool's launch: the command path and the variables it starts with.
struct AIProviderAdvancedPage: View {
    let kind: InstalledAIKind
    /// Where the automatic lookup found the command, shown so a set path can be compared with it.
    let foundCommand: URL?

    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @State private var commandPath = ""
    @State private var environmentText = ""
    /// A read that failed leaves the variables alone, so a save never writes blanks over them.
    @State private var environmentReadable = true
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.md) {
                        TextField("Command path", text: $commandPath, prompt: Text("Automatic"))
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                            .onSubmit(save)
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
                if !environmentReadable {
                    Label(
                        "The variables could not be read from the Keychain, so they can't be edited.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
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
        .scrollContentBackground(.hidden)
        .onAppear(perform: load)
        // Leaving the page, the provider or the panel is what saves it.
        .onDisappear(perform: save)
    }

    private var commandNote: (text: String, isProblem: Bool)? {
        switch InstalledAILaunch(commandPath: commandPath).command() {
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
            InstalledAILaunch(commandPath: commandPath).command().executableDirectory
            ?? foundCommand?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
        guard
            let url = ExecutablePicker.choose(
                message: "Choose the \(kind.command) command Onecast should run.",
                startingAt: start)
        else { return }
        commandPath = (url.path as NSString).abbreviatingWithTildeInPath
        save()
    }

    private func load() {
        commandPath = settings.override(for: kind).commandPath
        do {
            let variables = try settings.environment(for: kind)
            environmentText = AssistantSecretStore.format(
                Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.value) }))
        } catch {
            environmentReadable = false
        }
        loaded = true
    }

    /// The store ignores an unchanged launch, so saving on every exit re-checks nothing needlessly.
    private func save() {
        guard loaded else { return }
        settings.setCommandPath(commandPath, for: kind)
        guard environmentReadable else { return }
        let variables = AssistantSecretStore.parse(environmentText)
            .sorted { $0.key < $1.key }
            .map { InstalledAIVariable(name: $0.key, value: $0.value) }
        do {
            try settings.setEnvironment(variables, for: kind)
        } catch {
            core.showMessage(
                "\(kind.title)'s variables could not be saved to the Keychain", tone: .danger)
        }
    }
}

extension InstalledAILaunch.Command {
    /// The folder a set path points into, so the picker opens beside the command it names.
    fileprivate var executableDirectory: URL? {
        guard case .executable(let url) = self else { return nil }
        return url.deletingLastPathComponent()
    }
}
