import AppKit
import SwiftUI

/// The quicklink form controls, bound to a shared `QuicklinkDraft`. Both hosts — the Quicklinks
/// pane's sheet and the launcher's in-palette editor — render these same blocks and only differ in
/// how they arrange them, so a restyle here lands on both surfaces at once.

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
    let focus: FocusState<Bool>.Binding

    var body: some View {
        QuicklinkField(title: "Name") {
            TextField("Search GitHub", text: $draft.name)
                .dialogTextField()
                .focused(focus)
        }
    }
}

struct QuicklinkLinkField: View {
    @Bindable var draft: QuicklinkDraft

    var body: some View {
        QuicklinkField(title: "Link") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("https://github.com/search?q={argument}", text: $draft.link)
                        .dialogTextField()
                        .font(.body.monospaced())
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

    /// Only tokens meaningful in a destination; `{cursor}` and `{snippet:…}` stay literal.
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
    }
}

struct QuicklinkIconField: View {
    @Bindable var draft: QuicklinkDraft
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
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: draft.resolvedSymbol, size: 14)
                    Text(draft.iconSymbol == nil ? "Automatic" : "Custom")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .quicklinkControlSurface(width: 150)
            }
            .buttonStyle(.plain)
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
    @Environment(AppIndex.self) private var appIndex
    @State private var showingPicker = false

    var body: some View {
        QuicklinkField(title: "Open With") {
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if let bundleID = draft.openWithBundleID {
                        let app = AppPresentation.resolve(bundleID: bundleID, in: appIndex)
                        Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                        Text(app.name).lineLimit(1)
                    } else {
                        Text("Default app")
                    }
                    Spacer(minLength: 0)
                }
                .quicklinkControlSurface(width: 180)
            }
            .buttonStyle(.plain)
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

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .tint(Theme.Colors.textPrimary)
    }
}

private extension View {
    /// The control-surface capsule a picker button sits on, matching `dialogTextField`.
    func quicklinkControlSurface(width: CGFloat) -> some View {
        self
            .font(.body)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(width: width, height: Theme.Size.barButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
            .contentShape(Rectangle())
    }
}
