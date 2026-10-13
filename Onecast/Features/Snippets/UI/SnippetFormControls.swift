import SwiftUI

/// The snippet form controls, bound to a shared `SnippetDraft`. Both hosts — the Snippets pane's
/// sheet and the launcher's in-palette editor — render these same blocks and only differ in how they
/// arrange them. Every control is a Tab stop: it takes `focus`, so ⇥ walks name → keyword → template
/// → the two toggles in order, and each draws its own focused edge rather than AppKit's blue ring.
enum SnippetFormField: Int, CaseIterable, Hashable {
    case name, keyword, template, enabled, showsConfirmation

    /// ⇥ / ⇧⇥ wrap at either end, the way Raycast's form does.
    func advanced(backwards: Bool) -> SnippetFormField {
        let all = Self.allCases
        return all[(rawValue + (backwards ? -1 : 1) + all.count) % all.count]
    }
}

/// A titled control group, the form's repeated unit.
struct SnippetField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            content
        }
    }
}

struct SnippetNameField: View {
    @Bindable var draft: SnippetDraft
    var focus: FocusState<SnippetFormField?>.Binding
    @Environment(\.metrics) private var metrics

    var body: some View {
        SnippetField(title: "Name") {
            TextField("Email Sign-off", text: $draft.name)
                .dialogTextField()
                .focused(focus, equals: .name)
                .formFocusRing(focus.wrappedValue == .name, radius: metrics.radius.menu)
                .accessibilityHint("Required. Shown in the library and launcher.")
        }
    }
}

struct SnippetKeywordField: View {
    @Bindable var draft: SnippetDraft
    var focus: FocusState<SnippetFormField?>.Binding
    @Environment(\.metrics) private var metrics

    var body: some View {
        SnippetField(title: "Keyword") {
            TextField("Optional, for example !notes", text: $draft.keyword)
                .dialogTextField()
                .focused(focus, equals: .keyword)
                .formFocusRing(focus.wrappedValue == .keyword, radius: metrics.radius.menu)
                .accessibilityHint("Optional. Type this to expand the snippet.")
        }
    }
}

struct SnippetTemplateField: View {
    @Bindable var draft: SnippetDraft
    /// The text view is AppKit's, so it reports focus here rather than through a `FocusState`.
    @Binding var isFocused: Bool
    let moveFocus: (Bool) -> Void
    @State private var selection: TextSelection?
    @Environment(\.metrics) private var metrics

    var body: some View {
        SnippetField(title: "Template") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Spacer()
                    placeholderMenu
                }
                FormTextArea(
                    text: $draft.text, selection: $selection, focused: $isFocused,
                    minimumHeight: metrics.scaled(Theme.Size.editorTextHeight),
                    label: "Snippet template", isCode: true, moveFocus: moveFocus
                )
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
                .formFocusRing(isFocused, radius: Theme.Radius.row)
                .accessibilityHint("Enter the text Onecast expands. ⌥⇥ types a tab.")
            }
        }
    }

    /// Every placeholder the engine understands; parameters are in docs/features/snippets.md. Not a
    /// Tab stop: it seeds the editor beside it, which is where the focus is.
    private var placeholderMenu: some View {
        Menu("Insert…") {
            Section("Text") {
                placeholderItem("{cursor}")
                placeholderItem("{clipboard}")
                placeholderItem("{selection}")
                placeholderItem("{uuid}")
            }
            Section("Date & Time") {
                placeholderItem("{date}")
                placeholderItem("{time}")
                placeholderItem("{datetime}")
                placeholderItem("{day}")
            }
            Section("Arguments") {
                placeholderItem("{argument name=\"Name\"}")
            }
            Section("Snippets") {
                placeholderItem("{snippet name=\"Name\"}")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focusEffectDisabled()
        .accessibilityLabel("Insert a placeholder")
    }

    private func placeholderItem(_ token: String) -> some View {
        Button(token) { insert(token) }
    }

    private func insert(_ token: String) {
        let caret = draft.insert(token, replacing: selection?.singleRange)
        selection = TextSelection(insertionPoint: caret)
        isFocused = true
    }
}

struct SnippetOptionToggle: View {
    let title: String
    @Binding var isOn: Bool
    let detail: String
    let field: SnippetFormField
    var focus: FocusState<SnippetFormField?>.Binding

    var body: some View {
        FormCheckbox(title: title, detail: detail, isOn: $isOn, field: field, focus: focus)
    }
}
