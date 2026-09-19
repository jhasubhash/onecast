import SwiftUI

/// Identifies the editor to present; nil is "add", and the UUID keeps two opens distinct.
struct QuicklinkEditRequest: Identifiable {
    let id = UUID()
    var quicklink: Quicklink?
}

/// Add / edit sheet for a single quicklink, hosted by the Quicklinks pane. The launcher's in-palette
/// editor renders the same controls (`QuicklinkFormControls`) in its own layout; both bind a
/// `QuicklinkDraft`, so only chrome — title, buttons, width — differs between them. ⇥ / ⇧⇥ walk the
/// fields here too, so the pane and the launcher navigate identically.
struct QuicklinkEditorSheet: View {
    let dismiss: () -> Void

    @Environment(AppCore.self) private var core
    @State private var draft: QuicklinkDraft
    @FocusState private var focus: QuicklinkFormField?

    init(quicklink: Quicklink?, dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        _draft = State(initialValue: QuicklinkDraft(quicklink: quicklink))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(draft.title)
                .font(.title2.weight(.bold))

            QuicklinkNameField(draft: draft, focus: $focus)
            QuicklinkLinkField(draft: draft, focus: $focus)

            HStack(alignment: .bottom, spacing: Theme.Spacing.xl) {
                QuicklinkIconField(draft: draft, focus: $focus)
                QuicklinkOpenWithField(draft: draft, focus: $focus)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
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
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
        .onAppear { focus = .name }
        .onSubmit(save)
        // ⇥ walks the fields ourselves, so buttons and toggles are stops too and the caret never
        // escapes to the window chrome, matching the in-palette editor.
        .onKeyPress(keys: [.tab], phases: .down) { press in
            advanceFocus(backwards: press.modifiers.contains(.shift))
            return .handled
        }
    }

    private func advanceFocus(backwards: Bool) {
        let all = QuicklinkFormField.allCases
        let index = focus.flatMap { all.firstIndex(of: $0) } ?? 0
        focus = all[(index + (backwards ? -1 : 1) + all.count) % all.count]
    }

    private func save() {
        do {
            let quicklink = draft.build()
            if draft.isEditing {
                try core.quicklinkCoordinator.updateQuicklink(quicklink)
            } else {
                try core.quicklinkCoordinator.addQuicklink(quicklink)
            }
            dismiss()
        } catch {
            draft.errorMessage = error.localizedDescription
        }
    }
}
