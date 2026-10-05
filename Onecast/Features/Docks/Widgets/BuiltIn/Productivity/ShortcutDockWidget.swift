import AppKit
import OnecastPluginKit
import SwiftUI

/// Runs one Apple Shortcut on click; with none chosen, or ⌥ held, the click opens the picker.
@MainActor
final class ShortcutDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Shortcut", subtitle: "Runs one of your Apple Shortcuts", icon: AppleShortcut.sfSymbol,
        category: "Productivity", sizes: [.compact, .wide])

    private let library = ShortcutLibraryModel()

    /// ⌥ is read at the click: the dock asks for the popover as the pointer comes up.
    static var isChoosing: Bool { NSEvent.modifierFlags.contains(.option) }

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(ShortcutDockTile(context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        guard context.preferences.string(ProductivityPreferenceName.shortcut) == nil || Self.isChoosing
        else { return nil }
        return AnyView(ShortcutPickerPopover(context: context, library: library))
    }
}

/// The Shortcuts library as `shortcuts list` reports it, loaded when the picker opens.
@MainActor
@Observable
final class ShortcutLibraryModel {
    private(set) var shortcuts: [AppleShortcut] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var failure: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do throws(AppleShortcutRunner.Failure) {
            shortcuts = try await AppleShortcutRunner.list()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        hasLoaded = true
    }

    func shortcuts(matching query: String) -> [AppleShortcut] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return shortcuts }
        return shortcuts.filter { $0.name.localizedStandardContains(needle) }
    }
}

// MARK: - Tile

struct ShortcutDockTile: View {
    let context: DockWidgetContext
    @AppStorage private var name: String

    init(context: DockWidgetContext) {
        self.context = context
        _name = AppStorage(
            wrappedValue: "",
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.shortcut))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ProductivityTile(context: context) { geometry in
            Button(action: run) {
                ProductivityTileFace(
                    geometry: geometry,
                    color: trimmedName.isEmpty ? Theme.Colors.textTertiary : Color.accentColor,
                    label: "Shortcut",
                    caption: trimmedName.isEmpty ? "Choose a shortcut" : trimmedName,
                    captionColor: trimmedName.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary,
                    captionLines: geometry.isCompact ? 2 : 3
                ) {
                    SymbolImage(name: AppleShortcut.sfSymbol, size: geometry.pointSize(0.34))
                        .foregroundStyle(
                            trimmedName.isEmpty ? Theme.Colors.textTertiary : Color.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ProductivityPressStyle())
        }
        .accessibilityLabel(trimmedName.isEmpty ? "Choose a shortcut" : "Run \(trimmedName)")
    }

    private func run() {
        guard !trimmedName.isEmpty, !ShortcutDockWidget.isChoosing else { return }
        context.actions.runShortcut(trimmedName)
    }
}

// MARK: - Popover

struct ShortcutPickerPopover: View {
    let context: DockWidgetContext
    let library: ShortcutLibraryModel
    @AppStorage private var name: String
    @State private var query = ""

    init(context: DockWidgetContext, library: ShortcutLibraryModel) {
        self.context = context
        self.library = library
        _name = AppStorage(
            wrappedValue: "",
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.shortcut))
    }

    private var current: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ProductivityPopover {
            ProductivityPopoverHeader(title: "Shortcut", subtitle: subtitle)
            ProductivityField(prompt: "Filter shortcuts", text: $query, symbol: "magnifyingglass")
            content
            HStack(spacing: Theme.Spacing.md) {
                ProductivityPill(title: "Refresh", symbol: "arrow.clockwise") {
                    Task { await library.load() }
                }
                if !current.isEmpty {
                    ProductivityPill(title: "Clear", symbol: "xmark.circle") {
                        context.preferences.set(nil, for: ProductivityPreferenceName.shortcut)
                    }
                }
                Spacer(minLength: 0)
                ProductivityPill(title: "Open Shortcuts", symbol: "arrow.up.forward.app") {
                    context.actions.launchApp("com.apple.shortcuts")
                }
            }
        }
        .task { await library.load() }
    }

    private var subtitle: String {
        if current.isEmpty { return "Pick the one this tile runs" }
        let isMissing = library.hasLoaded && library.failure == nil
            && !library.shortcuts.contains { $0.name == current }
        return isMissing ? "“\(current)” isn't in your library" : "Runs “\(current)”"
    }

    @ViewBuilder
    private var content: some View {
        let matches = library.shortcuts(matching: query)
        if let failure = library.failure {
            ProductivityPopoverMessage(symbol: "exclamationmark.triangle", text: failure)
        } else if !library.hasLoaded {
            ProductivityPopoverMessage(symbol: AppleShortcut.sfSymbol, text: "Reading your shortcuts…")
        } else if library.shortcuts.isEmpty {
            ProductivityPopoverMessage(
                symbol: AppleShortcut.sfSymbol, text: "You have no shortcuts yet. Make one in Shortcuts.")
        } else if matches.isEmpty {
            ProductivityPopoverMessage(symbol: "magnifyingglass", text: "No shortcut matches “\(query)”.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    ForEach(matches) { shortcut in
                        ProductivityRowButton {
                            context.preferences.set(
                                shortcut.name, for: ProductivityPreferenceName.shortcut)
                            context.actions.closePopover()
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                SymbolImage(
                                    name: AppleShortcut.sfSymbol, size: DockProductivityMetrics.rowIcon
                                )
                                .foregroundStyle(Theme.Colors.textSecondary)
                                Text(shortcut.name)
                                    .font(Theme.Typography.rowTitle)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if shortcut.name == current {
                                    SymbolImage(name: "checkmark", size: Theme.Typography.menuSymbolSize)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: DockProductivityMetrics.popoverListMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
