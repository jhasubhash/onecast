import AppKit
import SwiftUI

// What a dock hangs off itself: a menu, a folder's contents, a widget's popover, a tile's label.
// Each is hosted in its own small panel, so none is clipped by the dock's window.

/// The environment a hosted dock view reads, resolved under Observation so a changed Interface
/// Size reaches a window that is already up.
private struct DockEnvironment: ViewModifier {
    let core: AppCore

    func body(content: Content) -> some View {
        content
            .environment(\.metrics, core.settings.interfaceSize.metrics)
            .environment(core)
            .environment(core.settings)
            .environment(core.palette)
    }
}

extension View {
    func dockEnvironment(_ core: AppCore) -> some View {
        modifier(DockEnvironment(core: core))
    }
}

// MARK: - Menu

@MainActor
@Observable
final class DockMenuState {
    var selection = 0
}

/// Onecast's own menu, in a panel of its own, since a context menu never matches its surface.
struct DockMenuView: View {
    let content: PopoverMenuContent
    @Bindable var state: DockMenuState
    let activate: (Int) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        PopoverMenu(
            header: content.header, items: content.items, selection: $state.selection,
            width: metrics.size.menuWidth, onActivate: activate)
    }
}

// MARK: - Label

/// A tile's name: the keycap vocabulary of Onecast's tooltip, on a surface of its own because a
/// label hung from a dock's own window would be cut off by it.
struct DockLabelView: View {
    let text: String
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text(text)
            .font(metrics.typography.keyCap)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, metrics.spacing.lg)
            .padding(.vertical, metrics.spacing.xs)
            .background(Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .clipShape(Capsule())
    }
}

// MARK: - Folder

@MainActor
@Observable
final class DockFolderPopoutModel {
    struct Entry: Identifiable, Sendable, Equatable {
        let path: String
        let name: String
        var id: String { path }
    }

    let path: String
    let title: String
    /// Nil until the listing lands.
    private(set) var entries: [Entry]?

    init(path: String, title: String) {
        self.path = path
        self.title = title
    }

    func load() async {
        let path = path
        entries = await Task.detached(priority: .userInitiated) { Self.list(path) }.value
    }

    nonisolated private static let entryLimit = 1000

    /// Finder's order, hidden files left out; a long folder is cut rather than read to the end.
    nonisolated private static func list(_ path: String) -> [Entry] {
        let url = URL(fileURLWithPath: path)
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.localizedNameKey],
                options: [.skipsHiddenFiles])) ?? []
        let entries = contents.map { item in
            let name =
                (try? item.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                ?? item.lastPathComponent
            return Entry(path: item.path, name: name)
        }
        return entries
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(entryLimit).map { $0 }
    }
}

/// The in-dock folder popout: a scrollable grid of what the folder holds, and a way out to Finder.
struct DockFolderPopoutView: View {
    let model: DockFolderPopoutModel
    let open: (DockFolderPopoutModel.Entry) -> Void
    let openInFinder: () -> Void
    @Environment(\.metrics) private var metrics

    private static let columns = 4
    private static let maxRows = 4
    private static let cellWidth: CGFloat = 88
    private static let cellHeight: CGFloat = 92
    private static let iconSide: CGFloat = 52

    var body: some View {
        let cell = metrics.scaled(Self.cellWidth)
        let width = cell * CGFloat(Self.columns) + metrics.spacing.xs * CGFloat(Self.columns - 1)
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            header
            content(cell: cell)
        }
        .padding(metrics.spacing.xl)
        .frame(width: width + metrics.spacing.xl * 2)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.dialog, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: metrics.spacing.md) {
            Text(model.title)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: metrics.spacing.md)
            BarButton(action: openInFinder) {
                HStack(spacing: metrics.spacing.xs) {
                    SymbolImage(name: "folder", size: metrics.scaled(Theme.Typography.menuSymbolSize))
                    Text("Open in Finder")
                        .font(metrics.typography.bar)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func content(cell: CGFloat) -> some View {
        let rowHeight = metrics.scaled(Self.cellHeight)
        if let entries = model.entries {
            if entries.isEmpty {
                Text("This folder is empty")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
            } else {
                grid(entries, cell: cell, rowHeight: rowHeight)
            }
        } else {
            Color.clear.frame(height: rowHeight)
        }
    }

    private func grid(_ entries: [DockFolderPopoutModel.Entry], cell: CGFloat, rowHeight: CGFloat)
        -> some View
    {
        let rows = (entries.count + Self.columns - 1) / Self.columns
        let visibleRows = min(rows, Self.maxRows)
        let height =
            rowHeight * CGFloat(visibleRows) + metrics.spacing.xs * CGFloat(max(visibleRows - 1, 0))
        let columns = Array(
            repeating: GridItem(.fixed(cell), spacing: metrics.spacing.xs), count: Self.columns)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: metrics.spacing.xs) {
                ForEach(entries) { entry in
                    DockFolderCell(
                        entry: entry, width: cell, height: rowHeight,
                        iconSide: metrics.scaled(Self.iconSide)
                    ) { open(entry) }
                }
            }
            .hideNativeScrollers()
        }
        .scrollIndicators(.never)
        .overflowFade(band: metrics.scaled(Theme.Size.menuOverflowFade), includingTop: true)
        .thinScrollbar()
        .frame(height: height)
    }
}

private struct DockFolderCell: View {
    let entry: DockFolderPopoutModel.Entry
    let width: CGFloat
    let height: CGFloat
    let iconSide: CGFloat
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            VStack(spacing: metrics.spacing.xs) {
                EntryIconView(source: .file(stamp: 0), fileURL: URL(fileURLWithPath: entry.path))
                    .frame(width: iconSide, height: iconSide)
                Text(entry.name)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
            }
            .padding(metrics.spacing.xs)
            .frame(width: width, height: height, alignment: .top)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(entry.name)
    }
}

// MARK: - Widget

/// A widget's popover on the panel recipe: the widget draws content, the dock draws the surface.
struct DockWidgetPopoverView: View {
    let content: AnyView
    @Environment(\.metrics) private var metrics

    var body: some View {
        content
            .padding(metrics.spacing.xl)
            .background(Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius.dialog, style: .continuous))
    }
}
