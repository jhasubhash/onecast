import SwiftUI

/// The snippet form controls, bound to a shared `SnippetDraft`. Both hosts — the Snippets pane's
/// sheet and the launcher's in-palette editor — render these same blocks and only differ in how they
/// arrange them. Every control is a Tab stop: it takes `focus`, so ⇥ walks name → keyword → template
/// → the two toggles in order, and each draws its own focused edge rather than AppKit's blue ring.
enum SnippetFormField: Int, CaseIterable, Hashable {
    case name, keyword, template, enabled, showsConfirmation
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
    var focus: FocusState<SnippetFormField?>.Binding
    @State private var selection: TextSelection?

    var body: some View {
        SnippetField(title: "Template") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Spacer()
                    placeholderMenu
                }
                TextEditor(text: $draft.text, selection: $selection)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: Theme.Size.editorTextHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
                    .contentShape(Rectangle())
                    .pointerStyle(.horizontalText)
                    .focused(focus, equals: .template)
                    .formFocusRing(focus.wrappedValue == .template, radius: Theme.Radius.row)
                    .accessibilityLabel("Snippet template")
                    .accessibilityHint("Enter the text Onecast expands.")
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

    /// Replaces the selection or lands at the caret; appends when there is no usable one.
    private func insert(_ token: String) {
        if let selection, case .selection(let range) = selection.indices,
            range.lowerBound >= draft.text.startIndex, range.upperBound <= draft.text.endIndex
        {
            draft.text.replaceSubrange(range, with: token)
        } else {
            draft.text += token
        }
        // Those indices belong to the replaced string, so they must not survive the next insert.
        selection = nil
        focus.wrappedValue = .template
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
