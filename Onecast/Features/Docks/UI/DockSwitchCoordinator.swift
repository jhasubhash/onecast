import AppKit

/// Every route into switching Docks, and the cleanup after a setup or dock is deleted.
@MainActor
final class DockSwitchCoordinator {
    private let store: DockStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    /// Dialogs, the message HUD and the palette; never state this type owns.
    private unowned let core: AppCore
    /// What the store held at the last pass, so a deletion reads differently from switching off.
    private var knownSetupIDs: Set<UUID>?
    private var knownDockIDs: Set<UUID>?

    init(
        store: DockStore, settings: AppSettings, appIndex: AppIndex, hotKeys: HotKeyManager,
        favorites: FavoritesStore, visibility: VisibilityStore, ranking: LauncherRankingStore,
        aliases: AliasStore, core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.core = core
    }

    // MARK: - Feature presence

    /// Idempotent: called from `DockCoordinator.applyEnabled()`, so a switch or an edit lands here.
    func applyLauncherPresence() {
        let configuration = store.configuration
        removeReferences(toMissingIn: configuration)
        let shown = settings.docksEnabled
        appIndex.setDocks(
            setups: shown ? configuration.setups : [], docks: shown ? configuration.docks : [])
        // Toggle Docks stays: it is the only launcher route back once the feature is off.
        appIndex.setCommandsVisible([.manageDocks], shown)
    }

    /// What no index prunes: a shortcut, favorite, alias or rank keyed to a setup or dock now gone.
    private func removeReferences(toMissingIn configuration: DockConfiguration) {
        let setups = Set(configuration.setups.map(\.id))
        let docks = Set(configuration.docks.map(\.id))
        let previousSetups = knownSetupIDs
        let previousDocks = knownDockIDs
        knownSetupIDs = setups
        knownDockIDs = docks
        for id in (previousSetups ?? []).subtracting(setups) {
            forget(.dockSetup(id), entryID: DockSetup.entryID(for: id))
        }
        for id in (previousDocks ?? []).subtracting(docks) {
            forget(.dockVisibility(id), entryID: CustomDock.entryID(for: id))
        }
    }

    private func forget(_ action: HotKeyAction, entryID: String) {
        if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
        hotKeys.setBinding(nil, for: action)
        favorites.remove(keys: [entryID])
        visibility.removeItemKeys([entryID])
        aliases.removeKeys([entryID])
        ranking.reset(itemKey: entryID)
    }

    // MARK: - Switching

    /// The one funnel for a launcher row, a shortcut, a link, the menu bar and the Focus filter.
    func switchToSetup(id: UUID) {
        guard settings.docksEnabled, store.setup(id: id) != nil else { return }
        dismissPalette()
        core.dockCoordinator.activateSetup(id: id)
    }

    func toggleDock(id: UUID) {
        guard settings.docksEnabled, let dock = store.dock(id: id) else { return }
        dismissPalette()
        core.dockCoordinator.setDockVisible(id: id, !dock.isVisible)
        core.showMessage(dock.isVisible ? "\(dock.name) hidden" : "\(dock.name) shown", tone: .neutral)
    }

    func activateLayout(dockID: UUID, layoutID: UUID) {
        guard settings.docksEnabled, let dock = store.dock(id: dockID),
            let layout = dock.layouts.first(where: { $0.id == layoutID })
        else { return }
        core.dockCoordinator.activateLayout(dockID: dockID, layoutID: layoutID)
        core.showMessage("\(dock.name) — \(layout.name)", tone: .neutral)
    }

    func applyNativeLayout(id: UUID) {
        guard settings.docksEnabled else { return }
        core.dockCoordinator.applyNativeLayout(id: id)
    }

    /// The command and its shortcut: the one switch that has to work while Docks is off.
    func toggleDocks() {
        let enabled = !settings.docksEnabled
        core.dockCoordinator.setDocksEnabled(enabled)
        core.showMessage(enabled ? "Docks on" : "Docks off", tone: .neutral)
    }

    func manageDocks() {
        dismissPalette()
        core.settingsCoordinator.showSettings(tab: .docks)
    }

    // MARK: - Links

    /// Runs a `onecast://dock/…` link, answering in the HUD when it names nothing.
    func handle(_ url: URL) {
        guard let link = DockURL.parse(url) else {
            core.showMessage("Not a Docks link", tone: .danger)
            return
        }
        guard settings.docksEnabled else {
            core.showMessage("Docks are off — turn them on in Settings", tone: .danger)
            return
        }
        let configuration = store.configuration
        switch link {
        case .setup(let reference):
            let candidates = configuration.setups.map { (id: $0.id, name: $0.name) }
            guard let id = DockURL.resolve(reference, among: candidates) else {
                return core.showMessage("No setup named “\(reference)”", tone: .danger)
            }
            switchToSetup(id: id)
        case .toggle(let reference):
            guard let id = resolveDock(reference, in: configuration) else {
                return core.showMessage("No dock named “\(reference)”", tone: .danger)
            }
            toggleDock(id: id)
        case .layout(let dockReference, let layoutReference):
            guard let dockID = resolveDock(dockReference, in: configuration),
                let dock = configuration.docks.first(where: { $0.id == dockID })
            else {
                return core.showMessage("No dock named “\(dockReference)”", tone: .danger)
            }
            let candidates = dock.layouts.map { (id: $0.id, name: $0.name) }
            guard let layoutID = DockURL.resolve(layoutReference, among: candidates) else {
                return core.showMessage(
                    "“\(dock.name)” has no layout named “\(layoutReference)”", tone: .danger)
            }
            activateLayout(dockID: dockID, layoutID: layoutID)
        }
    }

    private func resolveDock(_ reference: String, in configuration: DockConfiguration) -> UUID? {
        DockURL.resolve(reference, among: configuration.docks.map { (id: $0.id, name: $0.name) })
    }

    // MARK: - Backup

    /// Replaces the library from a backup, tidying the widget instances the swap orphans or adds.
    @discardableResult
    func replaceConfiguration(_ incoming: DockConfiguration) -> Int {
        let widgets = core.dockCoordinator.widgets
        let before = Self.widgetInstances(in: store.configuration)
        store.replace(with: incoming)
        let after = Self.widgetInstances(in: store.configuration)
        for id in Set(before.keys).subtracting(after.keys) { widgets.removeInstance(id) }
        for (id, widgetID) in after where before[id] == nil {
            widgets.registerDefaults(for: id, widgetID: widgetID)
        }
        return store.docks.count
    }

    private static func widgetInstances(in configuration: DockConfiguration) -> [UUID: String] {
        var instances: [UUID: String] = [:]
        for item in configuration.docks.flatMap(\.layouts).flatMap(\.items) {
            if case .widget(let reference) = item.kind { instances[item.id] = reference.widgetID }
        }
        return instances
    }

    // MARK: - Palette

    private func dismissPalette() {
        if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette() }
    }
}

extension DockColor {
    /// The tile a setup's launcher row wears; keyed apart from every other tint source.
    var entryTint: SymbolTint {
        let color: NSColor =
            switch self {
            case .blue: .systemBlue
            case .purple: .systemPurple
            case .pink: .systemPink
            case .red: .systemRed
            case .orange: .systemOrange
            case .yellow: .systemYellow
            case .green: .systemGreen
            case .teal: .systemTeal
            case .graphite: .systemGray
            }
        return SymbolTint(key: "dock." + rawValue, color: color)
    }
}
