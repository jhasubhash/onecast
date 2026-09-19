import AppKit
import SwiftUI

/// The quicklink form controls, bound to a shared `QuicklinkDraft`. Both hosts — the Quicklinks
/// pane's sheet and the launcher's in-palette editor — render these same blocks and only differ in
/// how they arrange them, so a restyle here lands on both surfaces at once. Every control is a Tab
/// stop: it takes `focus`, so ⇥ walks name → link → icon → open-with → the two toggles in order, and
/// each draws its own focused edge rather than AppKit's blue ring.
enum QuicklinkFormField: Int, CaseIterable, Hashable {
    case name, link, icon, openWith, showInRootSearch, pinned
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
    var focus: FocusState<QuicklinkFormField?>.Binding
    @Environment(\.metrics) private var metrics

    var body: some View {
        QuicklinkField(title: "Link") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("https://github.com/search?q={argument}", text: $draft.link)
                        .dialogTextField()
                        .focused(focus, equals: .link)
                        .formFocusRing(focus.wrappedValue == .link, radius: metrics.radius.menu)
                    insertMenu
                }
                destinationPreview
            }
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
            Button("Argument") { draft.insert("{argument}") }
            Button("Named Argument") { draft.insert("{argument name=\"Query\"}") }
            Divider()
            Button("Clipboard") { draft.insert("{clipboard}") }
            Button("Selected Text") { draft.insert("{selection}") }
            Divider()
            Button("Date") { draft.insert("{date}") }
            Button("Time") { draft.insert("{time}") }
            Button("Date & Time") { draft.insert("{datetime}") }
            Button("Custom Date Format") { draft.insert("{date format=\"yyyy-MM-dd\"}") }
            Divider()
            Button("UUID") { draft.insert("{uuid}") }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focusEffectDisabled()
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
