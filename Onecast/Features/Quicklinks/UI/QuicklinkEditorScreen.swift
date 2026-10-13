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
    func isPrimaryActionEnabled(at selection: Int) -> Bool { coordinator.editorDraft.isValid }
    func hasActions(at selection: Int) -> Bool { coordinator.editorDraft.isEditing }

    /// The wrapping link edits with ↑/↓, so only ⇥ leaves it; every other field steps the ring.
    func ownsVerticalKeys(at selection: Int) -> Bool {
        QuicklinkFormField.allCases[safe: selection] == .link
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
            PopoverMenuItem(
                title: "Delete Quicklink", systemImage: "trash", isDestructive: true
            ) { coordinator.deleteEditing() }
        ])
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let draft = coordinator.editorDraft
        return AnyView(
            QuicklinkEditorForm(coordinator: coordinator, draft: draft, vm: vm, selection: selection)
                .id(ObjectIdentifier(draft)))
    }
}

/// Lays the shared controls out in the panel and mirrors its flat selection onto its own focus.
private struct QuicklinkEditorForm: View {
    let coordinator: QuicklinkCoordinator
    @Bindable var draft: QuicklinkDraft
    let vm: PaletteState
    let selection: Int
    @FocusState private var focus: QuicklinkFormField?
    @State private var linkFocused = false

    private let fields = QuicklinkFormField.allCases

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.vertical, Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .hideNativeScrollers()
            }
            .edgeDissolve()
            .thinScrollbar()
            // The palette moves the selection with ⇥ and ↑/↓; focus follows it, and a click leads it.
            .onChange(of: selection) { _, sel in
                guard let field = fields[safe: sel] else { return }
                moveFocus(to: field)
                // SwiftUI keeps a newly focused field where it is, so a long link could hide it.
                proxy.scrollTo(field)
            }
        }
        // A focused single-line field's ↵ saves; a focusable button/toggle consumes its own ↵ first.
        .onSubmit { coordinator.saveEditor() }
        .onAppear {
            vm.noteEditingField(true)
            // The panel is key but not yet ready for a field to take first responder on the same tick
            // the screen mounts, so hand it the first field one runloop later.
            Task { @MainActor in moveFocus(to: fields[safe: selection] ?? .name) }
        }
        .onDisappear { vm.noteEditingField(false) }
        .onChange(of: focus) { _, field in
            vm.noteEditingField(field != nil || linkFocused)
            if let field, let index = fields.firstIndex(of: field), index != selection {
                vm.selection = index
            }
        }
        .onChange(of: linkFocused) { _, focused in vm.noteEditingField(focused || focus != nil) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                SymbolImage(name: draft.resolvedSymbol, size: 20)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(draft.title)
                    .font(.title3.weight(.bold))
            }

            QuicklinkNameField(draft: draft, focus: $focus).id(QuicklinkFormField.name)
            QuicklinkLinkField(
                draft: draft, isFocused: linkFocus, onSubmit: coordinator.saveEditor,
                moveFocus: { backwards in vm.selection = nextIndex(backwards: backwards) }
            )
            .id(QuicklinkFormField.link)

            HStack(alignment: .bottom, spacing: Theme.Spacing.xxl) {
                QuicklinkIconField(draft: draft, focus: $focus).id(QuicklinkFormField.icon)
                QuicklinkOpenWithField(draft: draft, focus: $focus).id(QuicklinkFormField.openWith)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                QuicklinkOptionToggle(
                    title: "Show in root search", isOn: $draft.showsInRootSearch,
                    detail: "List this quicklink alongside apps and commands.",
                    field: .showInRootSearch, focus: $focus
                )
                .id(QuicklinkFormField.showInRootSearch)
                QuicklinkOptionToggle(
                    title: "Pin to top", isOn: $draft.isPinned,
                    detail: "Keep it above the other quicklinks.",
                    field: .pinned, focus: $focus
                )
                .id(QuicklinkFormField.pinned)
            }

            if let errorMessage = draft.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// `focus` never names the link, an AppKit text view: SwiftUI drops a value no view owns.
    private func moveFocus(to field: QuicklinkFormField) {
        linkFocused = field == .link
        if field != .link { focus = field }
    }

    private var linkFocus: Binding<Bool> {
        Binding(
            get: { linkFocused },
            set: { focused in
                linkFocused = focused
                if focused { vm.selection = QuicklinkFormField.link.rawValue }
            })
    }

    private func nextIndex(backwards: Bool) -> Int {
        QuicklinkFormField.link.advanced(backwards: backwards).rawValue
    }
}
