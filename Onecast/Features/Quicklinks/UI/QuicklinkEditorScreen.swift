import SwiftUI

/// The quicklink editor as an in-palette form: the launcher panel morphs to host it, the search
/// field is hidden, and the palette's own footer carries the actions — Save on ↵ and, when editing,
/// Delete under ⌘K. The form owns no buttons of its own.
struct QuicklinkEditorScreen: PaletteScreen {
    /// The form owns the keyboard whole; it has no rows the palette selects between.
    struct Row: Identifiable { let id: Int }

    let coordinator: QuicklinkCoordinator
    let vm: PaletteState

    var rows: [Row] { [] }
    var hidesSearchField: Bool { true }
    var actsWithoutRows: Bool { true }
    var primaryActionTitle: String {
        coordinator.editorDraft.isEditing ? "Save Quicklink" : "Create Quicklink"
    }

    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func hasActions(at selection: Int) -> Bool { coordinator.editorDraft.isEditing }

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
        // Standard TextFields swallow ↵, so the panel's return handler never sees it; onSubmit lets a
        // focused single-line field save.
        AnyView(
            QuicklinkEditorForm(draft: coordinator.editorDraft, vm: vm)
                .onSubmit { activate(at: selection) })
    }
}

/// Lays the shared controls out to fit the fixed palette panel without scrolling, and hands the
/// keyboard to the form while it is up.
private struct QuicklinkEditorForm: View {
    @Bindable var draft: QuicklinkDraft
    let vm: PaletteState
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                SymbolImage(name: draft.resolvedSymbol, size: 20)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(draft.title)
                    .font(.title3.weight(.bold))
            }

            QuicklinkNameField(draft: draft, focus: $nameFocused)
            QuicklinkLinkField(draft: draft)

            HStack(alignment: .bottom, spacing: Theme.Spacing.xxl) {
                QuicklinkIconField(draft: draft)
                QuicklinkOpenWithField(draft: draft)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                QuicklinkOptionToggle(
                    title: "Show in root search", isOn: $draft.showsInRootSearch,
                    detail: "List this quicklink alongside apps and commands.")
                QuicklinkOptionToggle(
                    title: "Pin to top", isOn: $draft.isPinned,
                    detail: "Keep it above the other quicklinks.")
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
        .onAppear {
            vm.noteEditingField(true)
            // The panel is key but not yet ready for a field to take first responder on the same tick
            // the screen mounts, so hand it the Name field one runloop later.
            Task { @MainActor in nameFocused = true }
        }
        .onDisappear { vm.noteEditingField(false) }
    }
}
