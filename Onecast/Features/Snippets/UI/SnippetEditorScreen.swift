import SwiftUI

/// The snippet editor as an in-palette form: the launcher panel morphs to host it, the search field
/// is hidden, and the palette's own footer carries the actions — Save on ↵ and, when editing, Delete
/// under ⌘K. ⇥ / ⇧⇥ walk its fields through the palette's own field ring; the multi-line template
/// keeps ↑/↓ for its caret, so only ⇥ leaves it.
struct SnippetEditorScreen: PaletteScreen {
    /// One selectable stop per field, so the palette's flat selection is the focused field's index.
    struct Row: Identifiable { let id: Int }

    let coordinator: SnippetCoordinator
    let vm: PaletteState

    var rows: [Row] { SnippetFormField.allCases.indices.map { Row(id: $0) } }
    var hidesSearchField: Bool { true }
    var actsWithoutRows: Bool { true }
    var primaryActionTitle: String {
        coordinator.editorDraft.isEditing ? "Save Snippet" : "Create Snippet"
    }

    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func hasActions(at selection: Int) -> Bool { coordinator.editorDraft.isEditing }

    /// The multi-line template edits with ↑/↓, so only ⇥ leaves it; every other field steps the ring.
    func ownsVerticalKeys(at selection: Int) -> Bool {
        SnippetFormField.allCases[safe: selection] == .template
    }

    /// ⇥ / ⇧⇥ wrap at either end, the way Raycast's form does.
    func tabTarget(from selection: Int, backwards: Bool) -> Int? {
        let count = rows.count
        guard count > 0 else { return nil }
        return (selection + (backwards ? -1 : 1) + count) % count
    }

    func activate(at selection: Int) {
        coordinator.saveEditor()
    }

    func secondary(at selection: Int) -> Bool { false }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard coordinator.editorDraft.isEditing else { return nil }
        return PopoverMenuContent(items: [
            PopoverMenuItem(title: "Show in Finder", systemImage: "folder") {
                coordinator.revealEditingInFinder()
            },
            PopoverMenuItem(
                title: "Delete Snippet", systemImage: "trash", startsSection: true,
                isDestructive: true
            ) { coordinator.deleteEditing() }
        ])
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            SnippetEditorForm(
                coordinator: coordinator, draft: coordinator.editorDraft, vm: vm,
                selection: selection))
    }
}

/// Lays the shared controls out to fit the fixed palette panel, and mirrors the palette's flat
/// selection onto its own `@FocusState`, so ⇥ and ↑/↓ move the caret between fields.
private struct SnippetEditorForm: View {
    let coordinator: SnippetCoordinator
    @Bindable var draft: SnippetDraft
    let vm: PaletteState
    let selection: Int
    @FocusState private var focus: SnippetFormField?

    private let fields = SnippetFormField.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "curlybraces")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(draft.title)
                    .font(.title3.weight(.bold))
            }

            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                SnippetNameField(draft: draft, focus: $focus)
                SnippetKeywordField(draft: draft, focus: $focus)
            }

            SnippetTemplateField(draft: draft, focus: $focus)

            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                SnippetOptionToggle(
                    title: "Enabled", isOn: $draft.isEnabled,
                    detail: "Disabled snippets cannot be expanded.",
                    field: .enabled, focus: $focus)
                SnippetOptionToggle(
                    title: "Show confirmation", isOn: $draft.showsConfirmation,
                    detail: "Confirm on screen after this snippet is inserted.",
                    field: .showsConfirmation, focus: $focus)
            }

            if let errorMessage = draft.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A focused single-line field's ↵ saves; the template keeps ↵ for newlines, and a focusable
        // toggle consumes its own ↵ first.
        .onSubmit { coordinator.saveEditor() }
        .onAppear {
            vm.noteEditingField(true)
            Task { @MainActor in focus = fields[safe: selection] ?? .name }
        }
        .onDisappear { vm.noteEditingField(false) }
        .onChange(of: selection) { _, sel in
            if let field = fields[safe: sel] { focus = field }
        }
        .onChange(of: focus) { _, field in
            vm.noteEditingField(field != nil)
            if let field, let index = fields.firstIndex(of: field), index != selection {
                vm.selection = index
            }
        }
    }
}
