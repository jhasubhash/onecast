import SwiftUI

struct SnippetsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SnippetsStore.self) private var snippetsStore
    @Environment(AppSettings.self) private var settings

    @State private var pendingDeletion: StoredSnippet?
    @State private var editor: SnippetEditRequest?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .snippetsSnippets,
                enableTitle: "Enable snippets",
                enableSubtitle:
                    "Reusable Markdown templates, expanded from the launcher or a typed keyword.",
                launcherSubtitle: "Find your snippets in launcher search.",
                // Enabling is also keyword-expansion consent, so it uses the confirming setter.
                isEnabled: Binding(
                    get: { settings.snippetsEnabled },
                    set: { core.snippetCoordinator.setSnippetsEnabled($0) }),
                showsInLauncher: $settings.snippetsShowInLauncher)

            if settings.snippetsEnabled, core.snippetListener.status == .needsAccessibility {
                Section {
                    LabeledContent {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    } label: {
                        Label(
                            "Keyword expansion needs the Accessibility permission.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        Text(
                            "The same grant pasting uses. Launcher search keeps working meanwhile.")
                    }
                }
            }

            Group {
                FeatureCommandsSection(owner: .snippets, anchor: .snippetsCommands)
                library
                libraryNotices
            }
            .settingsEnabled(settings.snippetsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.snippets)
        // The pane edits inline; the launcher's "Create Snippet" opens its own in-palette editor.
        .sheet(item: $editor) { request in
            SnippetEditorSheet(record: request.record, dismiss: { editor = nil })
        }
        .alert(item: $pendingDeletion) { record in
            Alert(
                title: Text("Delete “\(record.snippet.name)”?"),
                message: Text(
                    "This removes \(record.fileURL.lastPathComponent) from your snippets folder."),
                primaryButton: .destructive(Text("Delete")) {
                    delete(record)
                },
                secondaryButton: .cancel())
        }
    }

    private var library: some View {
        Section {
            if sortedSnippets.isEmpty {
                Text(snippetsStore.state == .loading ? "Loading snippets…" : "No snippets yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedSnippets) { record in
                    SnippetSettingsRow(
                        record: record,
                        onEdit: { editor = SnippetEditRequest(record: record) },
                        onDelete: { pendingDeletion = record })
                }
            }

            LabeledContent {
                Button("Add…") { editor = SnippetEditRequest(record: nil) }
            } label: {
                SettingsRowTitle(.snippetsLibrary, "New Snippet")
                Text("Give the snippet a searchable name and an optional expansion keyword.")
            }

            LabeledContent {
                Button("Open Folder", action: core.snippetCoordinator.revealSnippetsInFinder)
                    .accessibilityHint("Reveals this Onecast channel’s snippets folder in Finder.")
            } label: {
                SettingsRowTitle(.snippetsLibrary, "Snippets Folder")
                Text("Plain Markdown files in this channel’s Application Support folder.")
            }
        } header: {
            SettingsSectionHeader(.snippetsLibrary)
        }
    }

    @ViewBuilder
    private var libraryNotices: some View {
        if case .failed(let message) = snippetsStore.state {
            noticeSection(
                "Couldn’t load the snippet library", message, tint: .orange,
                retryHint: "Tries to load the snippet library again.")
        }

        if !snippetsStore.issues.isEmpty {
            noticeSection(
                snippetIssueTitle, snippetIssueMessage, tint: .orange,
                retryHint: "Reloads snippet files after you fix them on disk.")
        }

        // The editor reports its own failures, so this covers the ones with no sheet behind.
        if editor == nil, let operationError = snippetsStore.operationError {
            noticeSection(
                "The snippet operation failed", operationError, tint: .red, retryHint: nil)
        }
    }

    private func noticeSection(
        _ title: String, _ message: String, tint: Color, retryHint: String?
    ) -> some View {
        Section {
            LabeledContent {
                if let retryHint {
                    Button("Retry", action: snippetsStore.retry)
                        .accessibilityHint(retryHint)
                }
            } label: {
                Label(title, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(tint)
                Text(message)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sortedSnippets: [StoredSnippet] {
        snippetsStore.snippets.sorted {
            $0.snippet.name.localizedCaseInsensitiveCompare($1.snippet.name) == .orderedAscending
        }
    }

    private var snippetIssueTitle: String {
        let count = snippetsStore.issues.count
        return count == 1
            ? "1 snippet file couldn’t be loaded" : "\(count) snippet files couldn’t be loaded"
    }

    private var snippetIssueMessage: String {
        let first = snippetsStore.issues[0]
        if snippetsStore.issues.count == 1 {
            return "\(first.fileURL.lastPathComponent): \(first.message)"
        }
        return
            "\(first.fileURL.lastPathComponent): \(first.message) Plus \(snippetsStore.issues.count - 1) more."
    }

    private func delete(_ record: StoredSnippet) {
        Task { try? await snippetsStore.delete(id: record.id) }
    }
}

struct SnippetEditRequest: Identifiable {
    let id = UUID()
    /// nil for a snippet that has no file yet.
    let record: StoredSnippet?
}

private struct SnippetSettingsRow: View {
    let record: StoredSnippet
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: record.snippet.name, subtitle: metadata) {
            Image(systemName: "doc.text")
        } trailing: {
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Snippet")
            .accessibilityLabel("Edit \(record.snippet.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Snippet")
            .accessibilityLabel("Delete \(record.snippet.name)")
        }
    }

    private var metadata: String {
        let filename = record.fileURL.lastPathComponent
        guard let keyword = record.snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
            !keyword.isEmpty
        else { return filename }
        return "\(keyword) · \(filename)"
    }
}

private struct SnippetEditorSheet: View {
    let dismiss: () -> Void

    @Environment(SnippetsStore.self) private var store
    @State private var draft: SnippetDraft
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    init(record: StoredSnippet?, dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        _draft = State(initialValue: SnippetDraft(record: record))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(draft.title)
                .font(.title2.weight(.bold))

            SnippetNameField(draft: draft, focus: $nameFocused)
            SnippetKeywordField(draft: draft)
            SnippetTemplateField(draft: draft)

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                SnippetOptionToggle(
                    title: "Enabled", isOn: $draft.isEnabled,
                    detail: "Disabled snippets cannot be expanded.")
                SnippetOptionToggle(
                    title: "Show confirmation", isOn: $draft.showsConfirmation,
                    detail: "Confirm on screen after this snippet is inserted.")
            }

            if let errorMessage = draft.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || !draft.isValid)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
        .onAppear { nameFocused = true }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // Saving keeps the revision, so an edit in between conflicts, not clobbers.
                if var updated = draft.editingRecord {
                    updated.snippet = draft.build()
                    try await store.save(updated)
                } else {
                    try await store.create(draft.build())
                }
                dismiss()
            } catch {
                draft.errorMessage = error.localizedDescription
            }
        }
    }
}
