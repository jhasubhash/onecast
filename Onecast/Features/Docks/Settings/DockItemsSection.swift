import AppKit
import SwiftUI

/// The selected layout's items: a strip to arrange them, a menu to add more, and the selected
/// item's own settings beneath.
struct DockItemsSection: View {
    let dockID: UUID
    let layoutID: UUID

    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store
    @State private var selectedItemID: UUID?
    @State private var showingAddMenu = false
    @State private var showingWidgetLibrary = false
    @State private var composer: Composer?

    private enum Composer {
        case link, shortcut
    }

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        if let dock = store.dock(id: dockID),
            let layout = dock.layouts.first(where: { $0.id == layoutID })
        {
            Section {
                DockItemStrip(items: layout.items, selection: $selectedItemID) { source, destination in
                    coordinator.moveItem(
                        dockID: dockID, layoutID: layoutID, from: source, to: destination)
                }
                .onChange(of: layoutID) {
                    selectedItemID = nil
                    composer = nil
                }

                Button {
                    showingAddMenu = true
                } label: {
                    SettingsRowTitle(.docksItems, "Add Item")
                }
                .popover(isPresented: $showingAddMenu, arrowEdge: .bottom) {
                    DockPopoverMenu(items: addMenuItems) { showingAddMenu = false }
                }
                .sheet(isPresented: $showingWidgetLibrary) {
                    DockWidgetLibrarySheet(dockID: dockID, layoutID: layoutID)
                }

                if composer == .link {
                    DockLinkComposer(
                        onAdd: { item in
                            coordinator.addItems([item], dockID: dockID, layoutID: layoutID)
                            composer = nil
                        },
                        onCancel: { composer = nil })
                } else if composer == .shortcut {
                    DockShortcutComposer(
                        onAdd: { name in
                            let item = DockItem(kind: .shortcut(name: name))
                            coordinator.addItems([item], dockID: dockID, layoutID: layoutID)
                            composer = nil
                        },
                        onCancel: { composer = nil })
                }

                if let index = layout.items.firstIndex(where: { $0.id == selectedItemID }) {
                    DockItemInspector(
                        dockID: dockID, layoutID: layoutID, item: layout.items[index],
                        index: index, count: layout.items.count,
                        onRemoved: { selectedItemID = nil })
                }
            } header: {
                SettingsSectionHeader(anchor: .docksItems) {
                    Text("\(SettingsAnchor.docksItems.title) · \(layout.name)")
                }
            } footer: {
                Text("Drag items to reorder them; select one to edit it.")
            }
        }
    }

    private var addMenuItems: [PopoverMenuItem] {
        [
            PopoverMenuItem(title: "Apps…", systemImage: "app") {
                coordinator.choose(.apps, dockID: dockID, layoutID: layoutID)
            },
            PopoverMenuItem(title: "Folders…", systemImage: "folder") {
                coordinator.choose(.folders, dockID: dockID, layoutID: layoutID)
            },
            PopoverMenuItem(title: "Files…", systemImage: "doc") {
                coordinator.choose(.files, dockID: dockID, layoutID: layoutID)
            },
            PopoverMenuItem(title: "Link…", systemImage: "link") { composer = .link },
            PopoverMenuItem(title: "Shortcut…", systemImage: AppleShortcut.sfSymbol) {
                composer = .shortcut
            },
            PopoverMenuItem(
                title: DockSpacerSize.small.settingsTitle, systemImage: "rectangle.dashed",
                startsSection: true
            ) { addSpacer(.small) },
            PopoverMenuItem(title: DockSpacerSize.regular.settingsTitle, systemImage: "square.dashed") {
                addSpacer(.regular)
            },
            PopoverMenuItem(
                title: "Widget…", systemImage: "square.grid.2x2", startsSection: true
            ) { showingWidgetLibrary = true },
        ]
    }

    private func addSpacer(_ size: DockSpacerSize) {
        coordinator.addItems(
            [DockItem(kind: .spacer(size))], dockID: dockID, layoutID: layoutID)
    }
}

/// What a typed link or symbol has to be before the dock can use it.
enum DockLinkInput {
    private static let bareSchemes = ["mailto:", "tel:", "sms:", "facetime:"]

    /// A web address typed without its scheme is read as https.
    static func normalizedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let hasScheme =
            trimmed.contains("://")
            || bareSchemes.contains { trimmed.lowercased().hasPrefix($0) }
        let candidate = hasScheme ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), url.scheme != nil else { return nil }
        if url.scheme == "http" || url.scheme == "https", url.host()?.isEmpty ?? true { return nil }
        return candidate
    }

    static func defaultTitle(for address: String) -> String {
        URL(string: address)?.host() ?? address
    }

    static func isSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
            || NSImage(named: name) != nil
    }
}

/// The inline form behind "Link…": a title, an address and an optional symbol.
private struct DockLinkComposer: View {
    let onAdd: (DockItem) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var address = ""
    @State private var symbol = ""

    private var normalizedAddress: String? { DockLinkInput.normalizedURL(address) }

    var body: some View {
        Group {
            LabeledContent("Title") {
                TextField("", text: $title, prompt: Text("The site's name"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: DockSettingsMetrics.nameFieldWidth)
            }

            LabeledContent("Address") {
                TextField("", text: $address, prompt: Text("example.com"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: DockSettingsMetrics.nameFieldWidth)
                    .onSubmit(add)
            }

            LabeledContent {
                TextField("", text: $symbol, prompt: Text("Website icon"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: DockSettingsMetrics.nameFieldWidth)
            } label: {
                Text("Symbol")
                Text("An SF Symbol name; blank uses the website's icon.")
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Link", action: add)
                    .disabled(normalizedAddress == nil)
            }
        }
    }

    private func add() {
        guard let address = normalizedAddress else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = DockLinkReference(
            url: address, title: name.isEmpty ? DockLinkInput.defaultTitle(for: address) : name,
            symbol: symbol.isEmpty ? nil : symbol)
        onAdd(DockItem(kind: .link(reference)))
    }
}

/// The inline list behind "Shortcut…", read from the Shortcuts app when it opens.
private struct DockShortcutComposer: View {
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    private enum Phase {
        case loading
        case loaded([AppleShortcut])
        case failed(String)
    }

    @State private var phase = Phase.loading
    @State private var choice: UUID?

    var body: some View {
        Group {
            switch phase {
            case .loading:
                HStack(spacing: Theme.Spacing.md) {
                    ProgressView().controlSize(.small)
                    Text("Reading your shortcuts…").foregroundStyle(.secondary)
                }
            case .failed(let message):
                LabeledContent {
                    Button("Try Again") { Task { await load() } }
                } label: {
                    Text("Couldn't read your shortcuts")
                        .foregroundStyle(.orange)
                    Text(message)
                }
            case .loaded(let shortcuts) where shortcuts.isEmpty:
                Text("No shortcuts yet. Create one in the Shortcuts app.")
                    .foregroundStyle(.secondary)
            case .loaded(let shortcuts):
                Picker(selection: $choice) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(shortcuts) { shortcut in
                        Text(shortcut.name).tag(UUID?.some(shortcut.id))
                    }
                } label: {
                    Text("Shortcut")
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Shortcut", action: add)
                    .disabled(selected == nil)
            }
        }
        .task { await load() }
    }

    private var selected: AppleShortcut? {
        guard case .loaded(let shortcuts) = phase else { return nil }
        return shortcuts.first { $0.id == choice }
    }

    private func add() {
        if let selected { onAdd(selected.name) }
    }

    private func load() async {
        phase = .loading
        do {
            phase = .loaded(try await AppleShortcutRunner.list())
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
