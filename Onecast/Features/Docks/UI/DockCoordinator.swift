import AppKit
import UniformTypeIdentifiers

/// The Docks feature's actions: every edit a pane or a dock makes goes through here to the store,
/// and every on-screen consequence (panels, the macOS Dock) is re-projected from the result.
@MainActor
final class DockCoordinator {
    private let store: DockStore
    private let settings: AppSettings
    private unowned let core: AppCore
    let panels: DockPanelController
    let nativeDock: NativeDockService
    let widgets: DockWidgetManager
    let windows: DockWindowObserver

    init(store: DockStore, settings: AppSettings, core: AppCore) {
        self.store = store
        self.settings = settings
        self.core = core
        panels = DockPanelController(core: core)
        nativeDock = NativeDockService()
        widgets = DockWidgetManager()
        windows = DockWindowObserver()
    }

    // MARK: - Lifecycle

    /// Called once from `AppCore.start()`, before the first `applyEnabled()`.
    func start() {
        nativeDock.recoverAfterCrash()
        nativeDock.onNativeLayoutChanged = { [weak self] tiles in
            self?.saveNativeDockChanges(tiles)
        }
        store.onChange = { [weak self] _ in self?.applyEnabled() }
    }

    /// Idempotent: re-projects the feature switch, the configuration and the widget consent.
    func applyEnabled() {
        let configuration = store.configuration
        let docksShown = settings.docksEnabled && configuration.nativeMode != .macOSOnly
        widgets.setThirdPartyEnabled(settings.docksEnabled && settings.dockWidgetsEnabled)
        panels.reconcile(configuration.docks, enabled: docksShown)
        nativeDock.applyHiding(
            hidden: docksShown && configuration.nativeMode == .customMain,
            hiding: configuration.nativeHiding)
        nativeDock.setObservingChanges(
            settings.docksEnabled && configuration.savesNativeDockChanges
                && configuration.activeNativeLayoutID != nil)
        let shown = docksShown ? configuration.docks.filter(\.isVisible) : []
        windows.setActive(
            minimizedWindows: shown.contains { $0.content.showsMinimizedWindows },
            badges: shown.contains { $0.content.showsBadges })
        core.dockSwitchCoordinator.applyLauncherPresence()
    }

    func prepareForTermination() {
        panels.closeAll()
        nativeDock.restoreForTermination()
    }

    /// Turning Docks on asks first when it would hide the macOS Dock.
    func setDocksEnabled(_ enabled: Bool) {
        guard enabled != settings.docksEnabled else { return }
        settings.docksEnabled = enabled
        if enabled, store.docks.isEmpty { addDock() }
    }

    /// Consent: DockWidgets are native code with Onecast's privileges, so turning them on confirms.
    func setDockWidgetsEnabled(_ enabled: Bool) {
        guard enabled != settings.dockWidgetsEnabled else { return }
        guard enabled else {
            settings.dockWidgetsEnabled = false
            return
        }
        Task {
            let confirmed = await core.confirm(
                title: "Allow third-party DockWidgets?",
                message: "A DockWidget is compiled Swift that runs inside Onecast with all of its "
                    + "permissions. Only install widgets whose source you have read.",
                symbol: "exclamationmark.shield", confirmTitle: "Allow",
                tone: .danger, confirmRole: .destructive)
            if confirmed { settings.dockWidgetsEnabled = true }
        }
    }

    // MARK: - Docks

    @discardableResult
    func addDock() -> CustomDock {
        let edges = Set(store.docks.map(\.placement.edge))
        let edge = DockEdge.allCases.first { !edges.contains($0) } ?? .bottom
        let dock = CustomDock(
            name: "Dock", placement: DockPlacement(edge: edge),
            layouts: [DockLayout(name: "Default", items: Self.starterItems())])
        return store.addDock(dock)
    }

    func removeDock(id: UUID) {
        guard let dock = store.dock(id: id) else { return }
        Task {
            let confirmed = await core.confirm(
                title: "Delete “\(dock.name)”?",
                message: "Its layouts and widgets are removed too.", symbol: "trash",
                confirmTitle: "Delete")
            guard confirmed else { return }
            for layout in dock.layouts { forgetWidgets(in: layout.items) }
            store.removeDock(id: id)
        }
    }

    func duplicateDock(id: UUID) {
        store.duplicateDock(id: id)
    }

    func renameDock(id: UUID, to name: String) {
        store.updateDock(id: id) { $0.name = name }
    }

    func setDockVisible(id: UUID, _ visible: Bool) {
        store.updateDock(id: id) { $0.isVisible = visible }
    }

    func updatePlacement(dockID: UUID, _ transform: (inout DockPlacement) -> Void) {
        store.updateDock(id: dockID) { transform(&$0.placement) }
    }

    func updateAppearance(dockID: UUID, _ transform: (inout DockAppearance) -> Void) {
        store.updateDock(id: dockID) { transform(&$0.appearance) }
    }

    func updateContent(dockID: UUID, _ transform: (inout DockContentOptions) -> Void) {
        store.updateDock(id: dockID) { transform(&$0.content) }
    }

    // MARK: - Layouts

    @discardableResult
    func addLayout(dockID: UUID, name: String = "Layout") -> DockLayout? {
        guard let dock = store.dock(id: dockID) else { return nil }
        let layout = DockLayout(
            name: DockStore.uniqueName(name, among: dock.layouts.map(\.name)),
            color: DockColor.allCases[dock.layouts.count % DockColor.allCases.count])
        store.updateDock(id: dockID) { $0.layouts.append(layout) }
        return layout
    }

    func duplicateLayout(dockID: UUID, layoutID: UUID) {
        guard let dock = store.dock(id: dockID),
            let original = dock.layouts.first(where: { $0.id == layoutID })
        else { return }
        let copy = DockLayout(
            name: DockStore.uniqueName(original.name + " Copy", among: dock.layouts.map(\.name)),
            color: original.color, items: original.items.map(\.copy))
        store.updateDock(id: dockID) { $0.layouts.append(copy) }
    }

    func removeLayout(dockID: UUID, layoutID: UUID) {
        guard let dock = store.dock(id: dockID), dock.layouts.count > 1,
            let layout = dock.layouts.first(where: { $0.id == layoutID })
        else { return }
        forgetWidgets(in: layout.items)
        store.updateDock(id: dockID) { $0.layouts.removeAll { $0.id == layoutID } }
    }

    func renameLayout(dockID: UUID, layoutID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.updateLayout(dockID: dockID, layoutID: layoutID) { $0.name = trimmed }
    }

    func setLayoutColor(dockID: UUID, layoutID: UUID, _ color: DockColor) {
        store.updateLayout(dockID: dockID, layoutID: layoutID) { $0.color = color }
    }

    func activateLayout(dockID: UUID, layoutID: UUID) {
        store.activateLayout(dockID: dockID, layoutID: layoutID)
    }

    /// A swipe or ⌘-scroll over a dock; the HUD names the layout it landed on.
    func stepLayout(dockID: UUID, by offset: Int) {
        guard let layout = store.stepLayout(dockID: dockID, by: offset) else { return }
        core.showMessage(layout.name, tone: .neutral)
    }

    // MARK: - Items

    func addItems(_ items: [DockItem], dockID: UUID, layoutID: UUID, at index: Int? = nil) {
        guard !items.isEmpty else { return }
        store.updateLayout(dockID: dockID, layoutID: layoutID) { layout in
            let position = min(max(index ?? layout.items.count, 0), layout.items.count)
            layout.items.insert(contentsOf: items, at: position)
        }
    }

    func updateItem(_ item: DockItem, dockID: UUID, layoutID: UUID) {
        store.updateLayout(dockID: dockID, layoutID: layoutID) { layout in
            guard let index = layout.items.firstIndex(where: { $0.id == item.id }) else { return }
            layout.items[index] = item
        }
    }

    func removeItem(id: UUID, dockID: UUID, layoutID: UUID) {
        guard let layout = store.dock(id: dockID)?.layouts.first(where: { $0.id == layoutID })
        else { return }
        forgetWidgets(in: layout.items.filter { $0.id == id })
        store.updateLayout(dockID: dockID, layoutID: layoutID) { layout in
            layout.items.removeAll { $0.id == id }
        }
    }

    func moveItem(dockID: UUID, layoutID: UUID, from source: Int, to destination: Int) {
        store.updateLayout(dockID: dockID, layoutID: layoutID) { layout in
            layout.items = DockSlots.move(layout.items, from: source, to: destination)
        }
    }

    /// Moves an item between docks or layouts as itself; a widget keeps its instance and settings.
    func transferItem(
        id: UUID, fromDock sourceDockID: UUID, layout sourceLayoutID: UUID,
        toDock dockID: UUID, layout layoutID: UUID, at index: Int
    ) {
        store.update { configuration in
            guard let from = Self.layoutIndex(sourceDockID, sourceLayoutID, in: configuration),
                let to = Self.layoutIndex(dockID, layoutID, in: configuration),
                let position = configuration.docks[from.dock].layouts[from.layout].items
                    .firstIndex(where: { $0.id == id })
            else { return }
            let item = configuration.docks[from.dock].layouts[from.layout].items.remove(at: position)
            let count = configuration.docks[to.dock].layouts[to.layout].items.count
            configuration.docks[to.dock].layouts[to.layout].items.insert(item, at: min(max(index, 0), count))
        }
    }

    private static func layoutIndex(
        _ dockID: UUID, _ layoutID: UUID, in configuration: DockConfiguration
    ) -> (dock: Int, layout: Int)? {
        guard let dock = configuration.docks.firstIndex(where: { $0.id == dockID }),
            let layout = configuration.docks[dock].layouts.firstIndex(where: { $0.id == layoutID })
        else { return nil }
        return (dock, layout)
    }

    /// Pins a running app at the end of a dock's active layout ("Keep in Dock").
    func keepInDock(_ app: DockRunningApp, dockID: UUID) {
        guard let dock = store.dock(id: dockID) else { return }
        let item = DockItem(kind: .app(DockAppReference(bundleID: app.bundleID, path: app.path)))
        addItems([item], dockID: dockID, layoutID: dock.activeLayoutID)
    }

    /// Items from URLs dropped on a dock or picked in a panel: apps, folders and files by kind.
    static func items(for urls: [URL]) -> [DockItem] {
        urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if url.pathExtension == "app" || values?.isPackage == true,
                let bundle = Bundle(url: url), bundle.bundleIdentifier != nil
            {
                return DockItem(
                    kind: .app(DockAppReference(bundleID: bundle.bundleIdentifier, path: url.path)))
            }
            if values?.isDirectory == true {
                return DockItem(kind: .folder(DockFolderReference(path: url.path)))
            }
            if !url.isFileURL {
                let title = url.host() ?? url.absoluteString
                return DockItem(kind: .link(DockLinkReference(url: url.absoluteString, title: title)))
            }
            return DockItem(kind: .file(path: url.path))
        }
    }

    enum PickerKind {
        case apps, folders, files
    }

    /// The system open panel; the one system surface Onecast keeps, since it is the file browser.
    func choose(_ kind: PickerKind, dockID: UUID, layoutID: UUID) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        switch kind {
        case .apps:
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.canChooseDirectories = false
        case .folders:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        case .files:
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
        }
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        addItems(Self.items(for: panel.urls), dockID: dockID, layoutID: layoutID)
    }

    func addWidget(_ widgetID: String, span: DockWidgetSpan, dockID: UUID, layoutID: UUID) {
        let item = DockItem(kind: .widget(DockWidgetReference(widgetID: widgetID, span: span)))
        widgets.registerDefaults(for: item.id, widgetID: widgetID)
        addItems([item], dockID: dockID, layoutID: layoutID)
    }

    private func forgetWidgets(in items: [DockItem]) {
        for item in items {
            guard case .widget = item.kind else { continue }
            widgets.removeInstance(item.id)
        }
    }

    // MARK: - macOS Dock

    func setNativeMode(_ mode: NativeDockMode) {
        store.update { $0.nativeMode = mode }
    }

    func setNativeHiding(_ hiding: NativeDockHiding) {
        store.update { $0.nativeHiding = hiding }
    }

    func setSavesNativeDockChanges(_ saves: Bool) {
        store.update { $0.savesNativeDockChanges = saves }
    }

    /// "Create from Current Dock": saves the macOS Dock's pinned apps and spacers as they are.
    @discardableResult
    func captureNativeLayout(name: String) -> NativeDockLayout? {
        do {
            let tiles = try nativeDock.readCurrentLayout()
            let layout = NativeDockLayout(
                name: DockStore.uniqueName(name, among: store.configuration.nativeLayouts.map(\.name)),
                tiles: tiles)
            store.update {
                $0.nativeLayouts.append(layout)
                if $0.activeNativeLayoutID == nil { $0.activeNativeLayoutID = layout.id }
            }
            return layout
        } catch {
            reportNativeFailure(error)
            return nil
        }
    }

    func replaceNativeLayoutWithCurrent(id: UUID) {
        Task {
            let confirmed = await core.confirm(
                title: "Replace with the current Dock?",
                message: "The layout's saved apps and spacers are replaced with what the macOS Dock "
                    + "shows now.", symbol: "dock.rectangle", confirmTitle: "Replace")
            guard confirmed else { return }
            do {
                let tiles = try nativeDock.readCurrentLayout()
                store.update { configuration in
                    guard let index = configuration.nativeLayouts.firstIndex(where: { $0.id == id })
                    else { return }
                    configuration.nativeLayouts[index].tiles = tiles
                }
            } catch {
                reportNativeFailure(error)
            }
        }
    }

    func applyNativeLayout(id: UUID) {
        guard let layout = store.nativeLayout(id: id) else { return }
        do {
            try nativeDock.apply(layout.tiles, layoutID: id)
            store.update { $0.activeNativeLayoutID = id }
        } catch {
            reportNativeFailure(error)
        }
    }

    func updateNativeLayout(_ layout: NativeDockLayout) {
        store.update { configuration in
            guard let index = configuration.nativeLayouts.firstIndex(where: { $0.id == layout.id })
            else { return }
            configuration.nativeLayouts[index] = layout
        }
    }

    func removeNativeLayout(id: UUID) {
        store.update { $0.nativeLayouts.removeAll { $0.id == id } }
    }

    private func saveNativeDockChanges(_ tiles: [NativeDockTile]) {
        guard let id = store.configuration.activeNativeLayoutID else { return }
        store.update { configuration in
            guard let index = configuration.nativeLayouts.firstIndex(where: { $0.id == id })
            else { return }
            configuration.nativeLayouts[index].tiles = tiles
        }
    }

    private func reportNativeFailure(_ error: Error) {
        Task {
            await core.showNotice(
                title: "Couldn't change the macOS Dock", message: error.localizedDescription,
                symbol: "dock.rectangle", tone: .danger)
        }
    }

    // MARK: - Setups

    @discardableResult
    func addSetup(name: String = "Setup") -> DockSetup {
        let configuration = store.configuration
        let setup = DockSetup(
            name: DockStore.uniqueName(name, among: configuration.setups.map(\.name)),
            color: DockColor.allCases[configuration.setups.count % DockColor.allCases.count],
            nativeLayoutID: configuration.activeNativeLayoutID,
            docks: configuration.docks.map {
                DockSetup.DockState(dockID: $0.id, isVisible: $0.isVisible, layoutID: $0.activeLayoutID)
            })
        store.update { $0.setups.append(setup) }
        return setup
    }

    func updateSetup(_ setup: DockSetup) {
        store.update { configuration in
            guard let index = configuration.setups.firstIndex(where: { $0.id == setup.id }) else {
                return
            }
            configuration.setups[index] = setup
        }
    }

    func removeSetup(id: UUID) {
        store.update { $0.setups.removeAll { $0.id == id } }
    }

    /// One switch for the whole setup: each custom dock's state, then the macOS Dock's layout.
    func activateSetup(id: UUID) {
        guard let setup = store.setup(id: id) else { return }
        store.activateSetup(id: id)
        if let native = setup.nativeLayoutID, native != nativeDock.lastAppliedLayoutID {
            applyNativeLayout(id: native)
        }
        core.showMessage(setup.name, tone: .neutral)
    }

    // MARK: - Starter content

    /// What a brand-new dock shows: Finder, Safari and the user's Applications folder.
    private static func starterItems() -> [DockItem] {
        let apps = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app"]
        var items = apps.compactMap { path -> DockItem? in
            guard let bundle = Bundle(path: path) else { return nil }
            return DockItem(
                kind: .app(DockAppReference(bundleID: bundle.bundleIdentifier, path: path)))
        }
        items.append(DockItem(kind: .spacer(.small)))
        items.append(DockItem(kind: .folder(DockFolderReference(path: "/Applications"))))
        return items
    }
}
