import AppKit
import SwiftUI

/// The rows of a dock's right-click menus, built from Onecast's own `PopoverMenuItem`.
@MainActor
enum DockMenus {
    @MainActor
    struct Context {
        let core: AppCore
        let dock: CustomDock
        let actions: DockItemActions

        var coordinator: DockCoordinator { core.dockCoordinator }
        var layoutID: UUID { dock.activeLayoutID }
    }

    // MARK: - Background

    /// Right-clicking the dock itself: layouts, what to add, and the dock's own settings.
    static func background(_ context: Context, showLayouts: @escaping () -> Void)
        -> PopoverMenuContent
    {
        let dock = context.dock
        let coordinator = context.coordinator
        var items: [PopoverMenuItem] = []
        if dock.layouts.count > 1 {
            var row = PopoverMenuItem(
                title: "Switch Layout", systemImage: "rectangle.stack", action: showLayouts)
            row.keepsMenuOpen = true
            row.trailingAccessory = { Self.chevron(detail: dock.activeLayout.name) }
            items.append(row)
        }
        items += [
            PopoverMenuItem(
                title: "Add Apps…", systemImage: "plus.app", startsSection: !items.isEmpty,
                action: { coordinator.choose(.apps, dockID: dock.id, layoutID: dock.activeLayoutID) }),
            PopoverMenuItem(
                title: "Add Folders…", systemImage: "folder.badge.plus",
                action: { coordinator.choose(.folders, dockID: dock.id, layoutID: dock.activeLayoutID) }
            ),
            PopoverMenuItem(
                title: "Add Files…", systemImage: "doc.badge.plus",
                action: { coordinator.choose(.files, dockID: dock.id, layoutID: dock.activeLayoutID) }),
            PopoverMenuItem(
                title: "Add Spacer", systemImage: "arrow.left.and.right",
                action: {
                    coordinator.addItems(
                        [DockItem(kind: .spacer(.regular))], dockID: dock.id,
                        layoutID: dock.activeLayoutID)
                }),
            PopoverMenuItem(
                title: "Add Widget…", systemImage: "square.grid.2x2",
                action: { context.core.settingsCoordinator.showSettings(tab: .docks) }),
            PopoverMenuItem(
                title: "Hide Dock", systemImage: "eye.slash", startsSection: true,
                action: { coordinator.setDockVisible(id: dock.id, false) }),
            PopoverMenuItem(
                title: "Dock Settings…", systemImage: "gearshape",
                action: { context.core.settingsCoordinator.showSettings(tab: .docks) }),
        ]
        return PopoverMenuContent(header: nil, items: items)
    }

    /// The second page of the background menu: every layout, the active one ticked.
    static func layouts(_ context: Context, back: @escaping () -> Void) -> PopoverMenuContent {
        let dock = context.dock
        var items: [PopoverMenuItem] = []
        var backRow = PopoverMenuItem(title: "Back", systemImage: "chevron.left", action: back)
        backRow.keepsMenuOpen = true
        items.append(backRow)
        for (offset, layout) in dock.layouts.enumerated() {
            let isActive = layout.id == dock.activeLayoutID
            items.append(
                PopoverMenuItem(
                    title: layout.name,
                    systemImage: isActive ? "checkmark.circle.fill" : "circle",
                    startsSection: offset == 0,
                    action: {
                        context.coordinator.activateLayout(dockID: dock.id, layoutID: layout.id)
                    }))
        }
        return PopoverMenuContent(header: "Switch Layout", items: items)
    }

    // MARK: - Tiles

    static func tile(_ slot: DockSlot, context: Context) -> PopoverMenuContent {
        let items: [PopoverMenuItem]
        switch slot {
        case .pinned(let item, let running):
            items = pinned(item, running: running, context: context)
        case .running(let app):
            items = unpinned(app, context: context)
        case .minimized(let window):
            items = [
                PopoverMenuItem(
                    title: "Restore", systemImage: "arrow.up.left.and.arrow.down.right",
                    action: { context.core.dockCoordinator.windows.restore(window.token) })
            ]
        case .trash:
            items = [
                PopoverMenuItem(
                    title: "Open Trash", systemImage: "trash", action: context.actions.openTrash),
                PopoverMenuItem(
                    title: "Empty Trash", systemImage: "trash.slash", startsSection: true,
                    isDestructive: true, action: context.actions.emptyTrash),
            ]
        case .divider:
            items = []
        }
        return PopoverMenuContent(header: nil, items: items)
    }

    private static func pinned(
        _ item: DockItem, running: DockRunningApp?, context: Context
    ) -> [PopoverMenuItem] {
        let actions = context.actions
        let remove = PopoverMenuItem(
            title: "Remove from Dock", systemImage: "minus.circle", startsSection: true,
            isDestructive: true,
            action: {
                context.coordinator.removeItem(
                    id: item.id, dockID: context.dock.id, layoutID: context.layoutID)
            })
        let options = PopoverMenuItem(
            title: "Options…", systemImage: "slider.horizontal.3",
            action: { context.core.settingsCoordinator.showSettings(tab: .docks) })

        switch item.kind {
        case .app(let reference):
            var rows = [
                PopoverMenuItem(
                    title: "Open", systemImage: "arrow.up.forward.app",
                    action: {
                        actions.activate(
                            reference, running: running,
                            minimizesWhenFocused: context.dock.content.clickFocusedAppMinimizes)
                    })
            ]
            if let bundleID = running?.bundleID {
                rows.append(
                    PopoverMenuItem(
                        title: "Quit", systemImage: "power", action: { actions.quit(bundleID: bundleID) }))
            }
            if let url = actions.resolvedURL(for: reference) {
                rows.append(
                    PopoverMenuItem(
                        title: "Show in Finder", systemImage: "folder",
                        action: { actions.showInFinder(path: url.path) }))
            }
            return rows + [remove]
        case .folder(let folder):
            return [
                PopoverMenuItem(
                    title: "Open", systemImage: "folder", action: { actions.open(path: folder.path) }),
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "magnifyingglass",
                    action: { actions.showInFinder(path: folder.path) }),
                options, remove,
            ]
        case .file(let path):
            return [
                PopoverMenuItem(
                    title: "Open", systemImage: "doc", action: { actions.open(path: path) }),
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "magnifyingglass",
                    action: { actions.showInFinder(path: path) }),
                remove,
            ]
        case .link(let link):
            return [
                PopoverMenuItem(
                    title: "Open", systemImage: "safari", action: { actions.open(link: link) }),
                options, remove,
            ]
        case .shortcut(let name):
            return [
                PopoverMenuItem(
                    title: "Run", systemImage: "play", action: { actions.runShortcut(named: name) }),
                remove,
            ]
        case .widget:
            return [options, remove]
        case .spacer:
            return [remove]
        }
    }

    private static func unpinned(_ app: DockRunningApp, context: Context) -> [PopoverMenuItem] {
        let actions = context.actions
        var rows = [
            PopoverMenuItem(
                title: "Open", systemImage: "arrow.up.forward.app",
                action: {
                    actions.activate(
                        app, minimizesWhenFocused: context.dock.content.clickFocusedAppMinimizes)
                })
        ]
        if let bundleID = app.bundleID {
            rows.append(
                PopoverMenuItem(
                    title: "Quit", systemImage: "power", action: { actions.quit(bundleID: bundleID) }))
        }
        rows += [
            PopoverMenuItem(
                title: "Show in Finder", systemImage: "folder",
                action: { actions.showInFinder(path: app.path) }),
            PopoverMenuItem(
                title: "Keep in Dock", systemImage: "pin", startsSection: true,
                action: { context.coordinator.keepInDock(app, dockID: context.dock.id) }),
        ]
        return rows
    }

    /// A row's trailing value and the chevron saying it opens another page.
    private static func chevron(detail: String) -> AnyView {
        AnyView(
            HStack(spacing: Theme.Spacing.xs) {
                Text(detail)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.disclosure)
                    .foregroundStyle(.secondary)
            })
    }
}

/// One open menu: its rows, the row the keyboard is on, and the pages it moves between.
@MainActor
final class DockMenuSession {
    let state = DockMenuState()
    private(set) var content: PopoverMenuContent
    private unowned let floating: DockFloatingController

    private static let upArrow: UInt16 = 126
    private static let downArrow: UInt16 = 125
    private static let returnKeys: Set<UInt16> = [36, 76]

    init(content: PopoverMenuContent, floating: DockFloatingController) {
        self.content = content
        self.floating = floating
        state.selection = content.items.firstIndex(where: \.isSelectable) ?? 0
    }

    var view: AnyView {
        AnyView(
            DockMenuView(content: content, state: state) { [weak self] index in
                self?.activate(index)
            })
    }

    /// Shows another page in the same window.
    func show(_ next: PopoverMenuContent) {
        content = next
        state.selection = next.items.firstIndex(where: \.isSelectable) ?? 0
        floating.replace(with: view)
    }

    func activate(_ index: Int) {
        guard content.items.indices.contains(index), content.items[index].isSelectable else {
            return
        }
        let item = content.items[index]
        if item.keepsMenuOpen {
            item.action()
            return
        }
        floating.close()
        item.action()
    }

    func handleKey(_ event: NSEvent) {
        switch event.keyCode {
        case Self.upArrow: move(by: -1)
        case Self.downArrow: move(by: 1)
        case _ where Self.returnKeys.contains(event.keyCode): activate(state.selection)
        default: break
        }
    }

    /// Skips rows that only state themselves, and stops at either end.
    private func move(by step: Int) {
        var index = state.selection + step
        while content.items.indices.contains(index) {
            if content.items[index].isSelectable {
                state.selection = index
                return
            }
            index += step
        }
    }
}
