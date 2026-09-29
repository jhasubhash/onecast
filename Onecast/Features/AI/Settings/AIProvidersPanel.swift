import AppKit
import SwiftUI

/// One provider in the panel's list; an installed tool, the on-device model, or an API connection.
enum AIProviderRoute: Hashable {
    case appleIntelligence
    case installed(InstalledAIKind)
    case api(UUID)

    var source: AIModelSource {
        switch self {
        case .appleIntelligence: return .appleIntelligence
        case .installed(let kind): return kind.source
        case .api(let id): return .api(id)
        }
    }
}

enum AIProviderPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case models = "Models"
    case advanced = "Advanced"

    var id: Self { self }

    /// A connection's models are the ones picked in its editor, so it has no Models page of its own.
    static func pages(for route: AIProviderRoute) -> [AIProviderPage] {
        switch route {
        case .appleIntelligence, .api: return [.overview]
        case .installed: return [.overview, .models, .advanced]
        }
    }
}

/// Settings → AI → Providers: Mail's Accounts shape, a provider list beside the selected one's pages.
struct AIProvidersPanel: View {
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    let onDone: () -> Void

    @State private var selection: AIProviderRoute?
    /// Kept across providers, as Mail keeps its tab across accounts; one without it shows Overview.
    @State private var page = AIProviderPage.overview
    @State private var keyStatuses: [UUID: Bool] = [:]
    @State private var keyError = false
    @State private var editor: AIConnectionEditorTarget?
    @State private var pendingRemoval: AIConnection?

    private let keyStore = KeychainSecretStore.aiAPIKeys

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("AI Providers").font(.title2.weight(.bold))
                Text("Installed tools, API connections, and the models each one offers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xl)
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: Theme.Size.aiProvidersList)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Stated, never intrinsic: selecting a longer provider must not resize the panel.
            .frame(height: Theme.Size.aiProvidersPanel.height)
            Divider()
            HStack {
                if keyError {
                    Label(
                        "The login Keychain could not be accessed.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .frame(width: Theme.Size.aiProvidersPanel.width)
        .releasesFocusOnOutsideClick()
        .sheet(item: $editor) { target in
            AIConnectionEditorSheet(
                target: target,
                onSave: saveConnection,
                onCancel: { editor = nil })
        }
        .confirmationDialog(
            pendingRemoval.map { "Remove “\($0.title)”?" } ?? "Remove connection?",
            isPresented: removalPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Connection", role: .destructive) {
                if let pendingRemoval { removeConnection(pendingRemoval) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its saved API key will also be deleted from Keychain.")
        }
        .onAppear {
            selection = selection ?? initialSelection
            loadKeyStatuses()
            core.applyInstalledAILifecycle()
        }
        .onChange(of: settings.connections.map(\.id)) { _, ids in
            if case .api(let id) = selection, !ids.contains(id) { selection = .installed(.codex) }
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("On This Mac") {
                    listRow(.appleIntelligence)
                }
                Section("Installed") {
                    ForEach(InstalledAIKind.allCases) { listRow(.installed($0)) }
                }
                Section("API Connections") {
                    if settings.connections.isEmpty {
                        Text("None yet")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                    ForEach(settings.connections) { listRow(.api($0.id)) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            listActions
        }
    }

    private func listRow(_ route: AIProviderRoute) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            AIProviderTile(icon: icon(for: route))
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(for: route))
                    .lineLimit(1)
                Text(caption(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .tag(route)
    }

    /// Mail's Accounts list: add below the list, and remove whatever it has selected.
    private var listActions: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button {
                editor = AIConnectionEditorTarget(
                    connection: AIConnection(), hasStoredKey: false, isNew: true)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add API Connection")
            .accessibilityLabel("Add API Connection")
            Button {
                pendingRemoval = selectedConnection
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(selectedConnection == nil)
            .help("Remove API Connection")
            .accessibilityLabel("Remove API Connection")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selection {
            let pages = AIProviderPage.pages(for: selection)
            let shown = pages.contains(page) ? page : .overview
            VStack(spacing: 0) {
                detailHeader(selection)
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.xl)
                if pages.count > 1 {
                    SteadySegmentedPicker(
                        title: "Page",
                        options: pages.map { .init(value: $0, title: $0.rawValue) },
                        selection: $page
                    )
                    .padding(.top, Theme.Spacing.xl)
                }
                pageContent(selection, page: shown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // A fresh page per provider, so one tool's unsaved field never shows under another.
            .id(selection)
        } else {
            ContentUnavailableView("Select a provider", systemImage: "sparkles")
        }
    }

    @ViewBuilder
    private func pageContent(_ route: AIProviderRoute, page: AIProviderPage) -> some View {
        switch (route, page) {
        case (.installed(let kind), .models):
            AIProviderModelsPage(
                source: kind.source, models: installedModels(kind),
                emptyNote: settings.enabledInstalledProviders.contains(kind)
                    ? "\(kind.title) has listed no models yet. Check it on Overview."
                    : "Turn \(kind.title) on to choose from its models.")
        case (.installed(let kind), .advanced):
            AIProviderAdvancedPage(kind: kind, foundCommand: executable(for: kind))
        case (.installed(let kind), .overview):
            detailForm { installedSections(kind) }
        case (.appleIntelligence, _):
            detailForm { appleIntelligenceSections }
        case (.api(let id), _):
            if let connection = settings.connection(id: id) {
                detailForm { connectionSections(connection) }
            }
        }
    }

    private func detailForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }

    private func detailHeader(_ route: AIProviderRoute) -> some View {
        HStack(spacing: Theme.Spacing.xl) {
            AIProviderTile(icon: icon(for: route), size: Theme.Size.settingsRowIcon * 1.5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(for: route))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(kindCaption(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.lg)
            switch route {
            case .installed(let kind):
                if let version = installedAI.status(for: kind).version,
                    settings.enabledInstalledProviders.contains(kind)
                {
                    Text("v" + version)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            case .api(let id):
                if let connection = settings.connection(id: id) {
                    Button("Edit…") { edit(connection) }
                }
            case .appleIntelligence:
                EmptyView()
            }
            routeToggle(route)
        }
    }

    // MARK: On this Mac

    @ViewBuilder
    private var appleIntelligenceSections: some View {
        let available = settings.isAppleIntelligenceAvailable()
        if !settings.isRouteEnabled(.appleIntelligence) { turnedOffSection() }
        Section {
            LabeledContent {
                Text(available ? "Ready" : "Unavailable")
                    .foregroundStyle(.secondary)
            } label: {
                Text(AppleIntelligence.title)
                Text(
                    available
                        ? "Runs on this Mac. Nothing leaves it."
                        : AppleIntelligenceProvider.status().message ?? "Not available on this Mac.")
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Choose the default model on the AI pane.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Installed commands

    @ViewBuilder
    private func installedSections(_ kind: InstalledAIKind) -> some View {
        if !settings.enabledInstalledProviders.contains(kind) {
            turnedOffSection(footer: installedFooter(kind))
        } else {
            Section {
                if kind == .codex {
                    codexStatusRows
                } else {
                    installedStatusRows(kind)
                }
            } header: {
                Text("Status")
            } footer: {
                Text(installedFooter(kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func turnedOffSection(footer: String? = nil) -> some View {
        Section {
            LabeledContent {
                EmptyView()
            } label: {
                Label("Turned off", systemImage: "pause.circle")
                Text("Onecast leaves it alone, and its models stay out of every model picker.")
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var codexStatusRows: some View {
        switch subscription.phase {
        case .idle, .starting:
            checkingRow("Codex")
        case .signedOut:
            signInRow(.codex, check: { subscription.refresh() })
        case .connected:
            LabeledContent {
                Button("Refresh") { subscription.refresh() }
            } label: {
                Text("Ready")
                Text(modelCount(subscription.models.count) + " available")
            }
            if let account = subscription.account {
                LabeledContent {
                    Text(
                        account.planTitle == "API key"
                            ? "Codex API key" : "ChatGPT \(account.planTitle)"
                    )
                    .foregroundStyle(.secondary)
                } label: {
                    Text("Account")
                    if let email = account.email { redacted(email) }
                }
            }
            if let limits = subscription.rateLimits {
                if let primary = limits.primary { usageRow(primary, fallbackTitle: "Primary window") }
                if let secondary = limits.secondary {
                    usageRow(secondary, fallbackTitle: "Secondary window")
                }
            }
            if let executable = subscription.executable { commandRow(executable) }
        case .unavailable(let message):
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Install Codex CLI…") {
                        NSWorkspace.shared.open(InstalledAIKind.codex.installURL)
                    }
                    Button("Check Again") { subscription.refresh() }
                }
                .fixedSize()
            } label: {
                Text("Not installed")
                Text(message)
            }
        case .failed(let message):
            failedRow(message, retry: { subscription.refresh() })
        }
    }

    @ViewBuilder
    private func installedStatusRows(_ kind: InstalledAIKind) -> some View {
        let status = installedAI.status(for: kind)
        switch status.phase {
        case .idle, .checking:
            checkingRow(kind.title)
        case .ready:
            LabeledContent {
                Button("Refresh") { installedAI.refresh(kind: kind) }
            } label: {
                Text("Ready")
                Text(modelCount(status.models.count) + " available")
            }
            if let account = status.account { accountRow(account, kind: kind) }
        case .signInRequired:
            signInRow(kind, check: { installedAI.refresh(kind: kind) })
        case .notInstalled:
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Install…") { NSWorkspace.shared.open(kind.installURL) }
                    Button("Check Again") { installedAI.refresh(kind: kind) }
                }
                .fixedSize()
            } label: {
                Text("Not installed")
                Text("Onecast could not find the \(kind.command) command.")
            }
        case .failed(let message):
            failedRow(message, retry: { installedAI.refresh(kind: kind) })
        }
        if let executable = status.executable { commandRow(executable) }
    }

    private func commandRow(_ executable: URL) -> some View {
        LabeledContent("Command") {
            Text((executable.path as NSString).abbreviatingWithTildeInPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func accountRow(_ account: InstalledAIAccount, kind: InstalledAIKind) -> some View {
        LabeledContent {
            if let plan = account.planTitle {
                Text("\(kind.title) \(plan)").foregroundStyle(.secondary)
            }
        } label: {
            Text("Account")
            if let email = account.email { redacted(email) }
        }
    }

    private func redacted(_ email: String) -> some View {
        RedactedText(
            value: email,
            revealHelp: "Click to reveal the signed-in account",
            hideHelp: "Click to hide the signed-in account")
    }

    private func checkingRow(_ title: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView().controlSize(.small)
            Text("Checking \(title)…").foregroundStyle(.secondary)
        }
    }

    private func signInRow(_ kind: InstalledAIKind, check: @escaping () -> Void) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Button("Copy Sign-In Command") { copySignInCommand(kind) }
                Button("Check Again", action: check)
            }
            .fixedSize()
        } label: {
            Text("Sign in required")
            Text("Run \(kind.signInCommand) in Terminal, then check again.")
        }
    }

    private func failedRow(_ message: String, retry: @escaping () -> Void) -> some View {
        LabeledContent {
            Button("Try Again", action: retry)
        } label: {
            Label("Check failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
        }
    }

    private func usageRow(
        _ window: ChatGPTSubscription.UsageWindow, fallbackTitle: String
    ) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView(value: Double(window.remainingPercent), total: 100)
                    .frame(width: Theme.Size.aiUsageBar)
                Text("\(window.remainingPercent)% left")
                    .monospacedDigit()
            }
        } label: {
            Text(usageTitle(window, fallback: fallbackTitle))
            if let reset = window.resetsAt {
                Text("Resets \(reset, style: .relative)")
            }
        }
    }

    private func installedFooter(_ kind: InstalledAIKind) -> String {
        "Uses the \(kind.command) command signed in on this Mac. Onecast never stores or asks for "
            + "its keys."
    }

    private func installedModels(_ kind: InstalledAIKind) -> [AIProviderModelsPage.Model] {
        if kind == .codex {
            guard subscription.isConnected else { return [] }
            return subscription.models.map { .init(id: $0.id, name: $0.name) }
        }
        let status = installedAI.status(for: kind)
        guard settings.enabledInstalledProviders.contains(kind), status.isReady else { return [] }
        return status.models.map { .init(id: $0.id, name: $0.name) }
    }

    private func executable(for kind: InstalledAIKind) -> URL? {
        kind == .codex ? subscription.executable : installedAI.status(for: kind).executable
    }

    // MARK: API connections

    @ViewBuilder
    private func connectionSections(_ connection: AIConnection) -> some View {
        if !settings.isRouteEnabled(.api(connection.id)) { turnedOffSection() }
        Section {
            LabeledContent("Provider") {
                Text(connection.provider.title).foregroundStyle(.secondary)
            }
            LabeledContent("Endpoint") {
                Text(connection.baseURL.isEmpty ? connection.provider.defaultBaseURL : connection.baseURL)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            LabeledContent("API key") {
                Text(keyStatus(connection))
                    .foregroundStyle(keyIsMissing(connection) ? .orange : .secondary)
            }
        } header: {
            Text("Connection")
        }
        Section {
            if connection.models.isEmpty {
                Text("No models yet. Add some with Edit….").foregroundStyle(.secondary)
            }
            ForEach(connection.models, id: \.self) { model in
                Text(model).font(.callout.monospaced())
            }
        } header: {
            Text("Models")
        } footer: {
            Text("Every model picked for this connection is listed in the model pickers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Naming

    private func title(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence: return AppleIntelligence.title
        case .installed(let kind): return kind.title
        case .api(let id): return settings.connection(id: id)?.title ?? "API Connection"
        }
    }

    private func kindCaption(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence: return "On this Mac · No account needed"
        case .installed(let kind): return "Installed command · \(kind.command)"
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return "API connection" }
            return "API connection · \(connection.provider.title)"
        }
    }

    private func caption(for route: AIProviderRoute) -> String {
        guard settings.isRouteEnabled(route.source) else { return "Off" }
        switch route {
        case .appleIntelligence:
            return settings.isAppleIntelligenceAvailable() ? "Ready" : "Unavailable"
        case .installed(.codex):
            switch subscription.phase {
            case .idle, .starting: return "Checking…"
            case .signedOut: return "Sign in required"
            case .unavailable: return "Not installed"
            case .failed: return "Check failed"
            case .connected: return "Ready · " + modelCount(subscription.models.count)
            }
        case .installed(let kind):
            let status = installedAI.status(for: kind)
            switch status.phase {
            case .idle, .checking: return "Checking…"
            case .ready: return "Ready · " + modelCount(status.models.count)
            case .signInRequired: return "Sign in required"
            case .notInstalled: return "Not installed"
            case .failed: return "Check failed"
            }
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return "" }
            if keyIsMissing(connection) { return "Key missing" }
            return modelCount(connection.models.count)
        }
    }

    private func icon(for route: AIProviderRoute) -> PopoverMenuIcon {
        switch route {
        case .appleIntelligence: return AIModelOption.appleIntelligenceIcon
        case .installed(.codex): return .asset(AIBrand.openAI.assetName)
        case .installed(.claude): return .asset(AIBrand.claude.assetName)
        case .installed(.openCode): return .asset(AIBrand.openCode.assetName)
        case .installed(.copilot): return .asset("BrandGitHub")
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return .symbol("sparkles") }
            return AIModelOption.icon(
                AIBrand.resolve(provider: connection.provider, model: connection.models.first ?? ""))
        }
    }

    private func modelCount(_ count: Int) -> String {
        count == 1 ? "1 model" : "\(count) models"
    }

    private func usageTitle(_ window: ChatGPTSubscription.UsageWindow, fallback: String) -> String {
        guard let minutes = window.durationMinutes else { return fallback }
        if minutes >= 1_440 { return "\(minutes / 1_440)-day window" }
        if minutes >= 60 { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }

    // MARK: - State

    /// Opens on the default model's provider, the one a reader most likely came to look at.
    private var initialSelection: AIProviderRoute {
        switch settings.defaultModel?.source {
        case .appleIntelligence?: return .appleIntelligence
        case .api(let id)?: return .api(id)
        case let source?: return source.installedKind.map(AIProviderRoute.installed) ?? .installed(.codex)
        case nil: return .installed(.codex)
        }
    }

    private var selectedConnection: AIConnection? {
        guard case .api(let id) = selection else { return nil }
        return settings.connection(id: id)
    }

    private func routeToggle(_ route: AIProviderRoute) -> some View {
        Toggle(
            "Enable \(title(for: route))",
            isOn: Binding(
                get: { settings.isRouteEnabled(route.source) },
                set: { settings.setRoute(route.source, enabled: $0) })
        )
        .labelsHidden()
        .toggleStyle(.switch)
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } })
    }

    private func keyIsMissing(_ connection: AIConnection) -> Bool {
        !AIEndpointPolicy.isLoopback(connection.baseURL) && keyStatuses[connection.id] != true
    }

    private func keyStatus(_ connection: AIConnection) -> String {
        if AIEndpointPolicy.isLoopback(connection.baseURL), keyStatuses[connection.id] != true {
            return "None needed"
        }
        return keyStatuses[connection.id] == true ? "In Keychain" : "Missing"
    }

    private func edit(_ connection: AIConnection) {
        editor = AIConnectionEditorTarget(
            connection: connection,
            hasStoredKey: keyStatuses[connection.id] == true,
            isNew: false)
    }

    private func saveConnection(
        _ connection: AIConnection, key: String, isNew: Bool
    ) -> String? {
        let outcome = AIConnectionKeyPolicy.resolve(
            enteredKey: key, connection: connection, saved: settings.connection(id: connection.id),
            hasStoredKey: keyStatuses[connection.id] == true)
        do {
            switch outcome {
            case .store(let key): try keyStore.setSecret(key, for: connection.id)
            case .removeStored: try keyStore.removeSecret(for: connection.id)
            case .keep: break
            case .reject(let message): return message
            }
            settings.save(connection)
            editor = nil
            loadKeyStatuses()
            settings.reconcile(subscription: subscription, installedAI: installedAI)
            if isNew { selection = .api(connection.id) }
            return nil
        } catch {
            keyError = true
            return isNew
                ? "The key could not be saved to Keychain."
                : "The saved key could not be updated in Keychain."
        }
    }

    private func removeConnection(_ connection: AIConnection) {
        do {
            try keyStore.removeSecret(for: connection.id)
            settings.removeConnection(id: connection.id)
            pendingRemoval = nil
            loadKeyStatuses()
        } catch {
            keyError = true
        }
    }

    private func copySignInCommand(_ kind: InstalledAIKind) {
        Paster.copyPlainText(kind.signInCommand)
        core.showMessage("Copied \(kind.signInCommand)")
    }

    private func loadKeyStatuses() {
        var statuses: [UUID: Bool] = [:]
        do {
            for connection in settings.connections {
                statuses[connection.id] = try keyStore.hasSecret(for: connection.id)
            }
            keyStatuses = statuses
            keyError = false
        } catch {
            keyStatuses = statuses
            keyError = true
        }
    }
}

/// The list and header glyph: a brand mark or symbol on the tile `SettingsTabIcon` draws.
private struct AIProviderTile: View {
    let icon: PopoverMenuIcon
    var size = Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2

    var body: some View {
        let scale = size / (Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2)
        glyph
            .frame(
                width: Theme.Size.settingsSidebarGlyph * scale,
                height: Theme.Size.settingsSidebarGlyph * scale
            )
            .foregroundStyle(.primary)
            .padding(Theme.Spacing.xs * scale)
            .background(
                Theme.Colors.controlSurface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail * scale, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .asset(let name):
            Image(name).resizable().renderingMode(.template).scaledToFit()
        case .symbol(let name):
            Image(systemName: name).resizable().scaledToFit()
        case .file, .thumbnail, .blank:
            Image(systemName: "sparkles").resizable().scaledToFit()
        }
    }
}

extension AISettingsStore {
    /// Moves the default model off any route that just went away, or onto its current catalogue.
    func reconcile(subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager) {
        let enabled = enabledInstalledProviders
        reconcile(
            codexModels: enabled.contains(.codex) ? subscription.models : [],
            isUnavailable: !enabled.contains(.codex) || subscription.phase == .signedOut
                || subscription.phase.isUnavailable)
        for kind in [InstalledAIKind.claude, .openCode, .copilot] {
            let status = installedAI.status(for: kind)
            reconcile(
                installed: kind,
                models: enabled.contains(kind) ? status.models : [],
                isUnavailable: !enabled.contains(kind) || status.phase == .signInRequired
                    || status.phase == .notInstalled)
        }
    }
}
