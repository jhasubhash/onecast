import SwiftUI

/// The quicklink editor as an in-palette form: the launcher panel morphs to host it, the search
/// field is hidden, and the palette's own footer carries the actions — Save on ↵ and, when editing,
/// Delete under ⌘K. ⇥ / ⇧⇥ walk its fields through the palette's own field ring, so the form owns no
/// buttons and no Tab handler of its own.
struct QuicklinkEditorScreen: PaletteScreen {
    /// One selectable stop per field, so the palette's flat selection is the focused field's index.
    struct Row: Identifiable { let id: Int }

    let coordinator: QuicklinkCoordinator
    let vm: PaletteState

    var rows: [Row] { QuicklinkFormField.allCases.indices.map { Row(id: $0) } }
    var hidesSearchField: Bool { true }
    var actsWithoutRows: Bool { true }
    var primaryActionTitle: String {
        coordinator.editorDraft.isEditing ? "Save Quicklink" : "Create Quicklink"
    }

    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func hasActions(at selection: Int) -> Bool { coordinator.editorDraft.isEditing }

    /// No field edits with ↑/↓, so they step the field ring like ⇥ does — Raycast's form behaviour.
    func ownsVerticalKeys(at selection: Int) -> Bool { false }

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
            PopoverMenuItem(
                title: "Delete Quicklink", systemImage: "trash", isDestructive: true
            ) { coordinator.deleteEditing() }
        ])
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            QuicklinkEditorForm(
                coordinator: coordinator, draft: coordinator.editorDraft, vm: vm,
                selection: selection))
    }
}

/// Lays the shared controls out to fit the fixed palette panel without scrolling, and mirrors the
/// palette's flat selection onto its own `@FocusState`, so ⇥ and ↑/↓ move the caret between fields.
private struct QuicklinkEditorForm: View {
    let coordinator: QuicklinkCoordinator
    @Bindable var draft: QuicklinkDraft
    let vm: PaletteState
    let selection: Int
    @FocusState private var focus: QuicklinkFormField?

    private let fields = QuicklinkFormField.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                SymbolImage(name: draft.resolvedSymbol, size: 20)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(draft.title)
                    .font(.title3.weight(.bold))
            }

            QuicklinkNameField(draft: draft, focus: $focus)
            QuicklinkLinkField(draft: draft, focus: $focus)

            HStack(alignment: .bottom, spacing: Theme.Spacing.xxl) {
                QuicklinkIconField(draft: draft, focus: $focus)
                QuicklinkOpenWithField(draft: draft, focus: $focus)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                QuicklinkOptionToggle(
                    title: "Show in root search", isOn: $draft.showsInRootSearch,
                    detail: "List this quicklink alongside apps and commands.",
                    field: .showInRootSearch, focus: $focus)
                QuicklinkOptionToggle(
                    title: "Pin to top", isOn: $draft.isPinned,
                    detail: "Keep it above the other quicklinks.",
                    field: .pinned, focus: $focus)
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
        // A focused single-line field's ↵ saves; a focusable button/toggle consumes its own ↵ first.
        .onSubmit { coordinator.saveEditor() }
        .onAppear {
            vm.noteEditingField(true)
            // The panel is key but not yet ready for a field to take first responder on the same tick
            // the screen mounts, so hand it the first field one runloop later.
            Task { @MainActor in focus = fields[safe: selection] ?? .name }
        }
        .onDisappear { vm.noteEditingField(false) }
        // The palette moves the selection with ⇥ and ↑/↓; focus follows it, and a click leads it.
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
