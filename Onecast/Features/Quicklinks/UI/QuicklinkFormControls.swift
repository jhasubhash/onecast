import AppKit
import SwiftUI

/// The quicklink form controls, bound to a shared `QuicklinkDraft`. Both hosts — the Quicklinks
/// pane's sheet and the launcher's in-palette editor — render these same blocks and only differ in
/// how they arrange them, so a restyle here lands on both surfaces at once. Every control is a Tab
/// stop: it takes `focus`, so ⇥ walks name → link → icon → open-with → the two toggles in order, and
/// each draws its own focused edge rather than AppKit's blue ring.
enum QuicklinkFormField: Int, CaseIterable, Hashable {
    case name, link, icon, openWith, showInRootSearch, pinned

    /// ⇥ / ⇧⇥ wrap at either end, the way Raycast's form does.
    func advanced(backwards: Bool) -> QuicklinkFormField {
        let all = Self.allCases
        return all[(rawValue + (backwards ? -1 : 1) + all.count) % all.count]
    }
}

/// A titled control group, the form's repeated unit.
struct QuicklinkField<Content: View>: View {
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

struct QuicklinkNameField: View {
    @Bindable var draft: QuicklinkDraft
    var focus: FocusState<QuicklinkFormField?>.Binding
    @Environment(\.metrics) private var metrics

    var body: some View {
        QuicklinkField(title: "Name") {
            TextField("Search GitHub", text: $draft.name)
                .dialogTextField()
                .focused(focus, equals: .name)
                .formFocusRing(focus.wrappedValue == .name, radius: metrics.radius.menu)
        }
    }
}

struct QuicklinkLinkField: View {
    @Bindable var draft: QuicklinkDraft
    /// The text view is AppKit's, so it reports focus here rather than through a `FocusState`.
    @Binding var isFocused: Bool
    let onSubmit: () -> Void
    let moveFocus: (Bool) -> Void
    @State private var selection: TextSelection?
    @Environment(\.metrics) private var metrics

    var body: some View {
        QuicklinkField(title: "Link") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    linkArea
                    insertMenu
                        .padding(.top, metrics.spacing.md)
                }
                destinationPreview
            }
        }
    }

    /// A link wraps rather than scrolls, and stays one line: ↵ saves and a pasted break flattens.
    private var linkArea: some View {
        FormTextArea(
            text: $draft.link, selection: $selection, focused: $isFocused, minimumHeight: 0,
            label: "Link", isCode: true, allowsLineBreaks: false, onSubmit: onSubmit,
            moveFocus: moveFocus
        )
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .overlay(alignment: .topLeading) { placeholder }
        .formFocusRing(isFocused, radius: metrics.radius.menu)
    }

    @ViewBuilder
    private var placeholder: some View {
        if draft.link.isEmpty {
            Text("https://github.com/search?q={argument}")
                .font(.system(size: metrics.typography.nsFont(.body).pointSize, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.vertical, metrics.spacing.md)
                .allowsHitTesting(false)
        }
    }

    /// The destination as it will be opened: all the feedback a templated link can give.
    @ViewBuilder
    private var destinationPreview: some View {
        let value = draft.trimmedLink
        if value.isEmpty {
            EmptyView()
        } else if QuicklinkDestination.containsPlaceholder(value) {
            Text("Resolved when you open it — placeholders are filled in first.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else if let destination = QuicklinkDestination.detect(value) {
            Label(destination.displayText, systemImage: destination.defaultSymbol)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("This doesn't look like a URL, file path, or deeplink.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// Only tokens meaningful in a destination; `{cursor}` and `{snippet:…}` stay literal. Not a Tab
    /// stop: it seeds the field beside it, which is where the focus is.
    private var insertMenu: some View {
        Menu("Insert…") {
            insertItem("Argument", "{argument}")
            insertItem("Named Argument", "{argument name=\"Query\"}")
            Divider()
            insertItem("Clipboard", "{clipboard}")
            insertItem("Selected Text", "{selection}")
            Divider()
            insertItem("Date", "{date}")
            insertItem("Time", "{time}")
            insertItem("Date & Time", "{datetime}")
            insertItem("Custom Date Format", "{date format=\"yyyy-MM-dd\"}")
            Divider()
            insertItem("UUID", "{uuid}")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focusEffectDisabled()
    }

    private func insertItem(_ title: String, _ token: String) -> some View {
        Button(title) { insert(token) }
    }

    private func insert(_ token: String) {
        let caret = draft.insert(token, replacing: selection?.singleRange)
        selection = TextSelection(insertionPoint: caret)
        isFocused = true
    }
}

struct QuicklinkIconField: View {
    @Bindable var draft: QuicklinkDraft
    var focus: FocusState<QuicklinkFormField?>.Binding
    @State private var showingPicker = false

    private static let symbols = [
        "globe", "folder", "doc.text", "link", "star", "bookmark", "magnifyingglass", "cart",
        "envelope", "message", "calendar", "clock", "checklist", "chart.bar", "hammer", "wrench",
        "ladybug", "terminal", "chevron.left.forwardslash.chevron.right", "cloud", "server.rack",
        "lock", "person.2", "building.2", "graduationcap", "book", "music.note", "play.rectangle",
        "photo", "paintbrush", "creditcard", "map"
    ]

    var body: some View {
        QuicklinkField(title: "Icon") {
            FormControlButton(
                width: 150, field: .icon, focus: focus, action: { showingPicker = true }
            ) {
                SymbolImage(name: draft.resolvedSymbol, size: 14)
                Text(draft.iconSymbol == nil ? "Automatic" : "Custom").lineLimit(1)
                Spacer(minLength: 0)
            }
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                SymbolPicker(
                    selection: $draft.iconSymbol, fallback: draft.automaticSymbol,
                    symbols: Self.symbols
                ) {
                    showingPicker = false
                }
            }
        }
    }
}

struct QuicklinkOpenWithField: View {
    @Bindable var draft: QuicklinkDraft
    var focus: FocusState<QuicklinkFormField?>.Binding
    @Environment(AppIndex.self) private var appIndex
    @State private var showingPicker = false

    var body: some View {
        QuicklinkField(title: "Open With") {
            FormControlButton(
                width: 180, field: .openWith, focus: focus, action: { showingPicker = true }
            ) {
                if let bundleID = draft.openWithBundleID {
                    let app = AppPresentation.resolve(bundleID: bundleID, in: appIndex)
                    Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                    Text(app.name).lineLimit(1)
                } else {
                    Text("Default app")
                }
                Spacer(minLength: 0)
            }
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                AppPickerPopover(clearTitle: "Default app") { bundleID in
                    draft.openWithBundleID = bundleID
                    showingPicker = false
                }
            }
        }
    }
}

struct QuicklinkOptionToggle: View {
    let title: String
    @Binding var isOn: Bool
    let detail: String
    let field: QuicklinkFormField
    var focus: FocusState<QuicklinkFormField?>.Binding

    var body: some View {
        FormCheckbox(title: title, detail: detail, isOn: $isOn, field: field, focus: focus)
    }
}
