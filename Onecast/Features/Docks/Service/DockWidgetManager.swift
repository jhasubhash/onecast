import AppKit
import OnecastPluginKit
import SwiftUI

/// One widget as the library and the dock editor list it: a built-in or an installed manifest.
struct DockWidgetDescriptor: Identifiable {
    let id: String
    let metadata: DockWidgetMetadata
    let preferences: [PluginPreference]
    let isBuiltIn: Bool
}

/// What a dock tile can show for a widget instance.
enum DockWidgetInstanceState: Equatable {
    case loading
    case ready
    /// A build or load error, or a widget that is no longer installed.
    case failed(String)
    /// A third-party widget while third-party DockWidgets are off.
    case unavailable
}

/// A built DockWidget dylib's entry point. The host calls `make` once per instance.
struct DockWidgetFactory {
    let name: String
    let create: OnecastDockWidgetCreate

    @MainActor
    func make() -> (any OnecastDockWidget)? {
        OnecastDockWidgetRuntime.consume(create())
    }
}

extension DockWidgetInstall: PluginSource {
    var kind: PluginSourceKind { .dockWidget }
    var displayName: String { manifest.name }
}

extension DockWidgetSpan {
    var widgetSize: DockWidgetSize {
        switch self {
        case .compact: .compact
        case .wide: .wide
        case .expanded: .expanded
        }
    }
}

extension DockEdge {
    var widgetEdge: DockWidgetEdge {
        switch self {
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        }
    }
}

/// The widget library plus one live object per dock instance; third-party loading needs consent.
@MainActor
@Observable
final class DockWidgetManager {
    private(set) var installed: [DockWidgetInstall] = []
    private(set) var isThirdPartyEnabled = false
    /// False until the first scan lands, so a saved third-party tile reads as loading, not missing.
    private(set) var hasScanned = false
    /// Bumped when Settings edits an instance's preference, so tiles re-ask `tile(context:)`.
    private(set) var preferencesRevision = 0
    private var builds: [String: Build] = [:]

    /// Routed by the surface, which owns the popover windows; the manager never touches one.
    @ObservationIgnored var onClosePopover: ((UUID) -> Void)?
    /// The data sources built-in widgets share, owned here so `AppCore` owns them.
    @ObservationIgnored let services = DockWidgetServices()

    @ObservationIgnored private var live: [UUID: LiveWidget] = [:]
    @ObservationIgnored private var widgetIDs: [UUID: String] = [:]
    @ObservationIgnored private var instanceFailures: [UUID: String] = [:]
    /// The source hash last queued per widget, so an unchanged scan never rebuilds.
    @ObservationIgnored private var requested: [String: String] = [:]
    @ObservationIgnored private var buildQueue: [DockWidgetInstall] = []
    @ObservationIgnored private var isBuilding = false
    @ObservationIgnored private var watcher: DockWidgetFolderWatcher?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = 0

    private enum Build {
        case ready(DockWidgetFactory)
        case failed(String)
    }

    private struct LiveWidget {
        let widgetID: String
        let widget: any OnecastDockWidget
    }

    init() {}

    // MARK: - Consent

    func setThirdPartyEnabled(_ enabled: Bool) {
        guard enabled != isThirdPartyEnabled else { return }
        isThirdPartyEnabled = enabled
        guard enabled else {
            stopWatching()
            buildQueue = []
            retire { _, entry in !entry.widgetID.hasPrefix(DockWidgetManifest.reservedPrefix) }
            installed = []
            builds = [:]
            requested = [:]
            hasScanned = false
            return
        }
        refresh()
    }

    // MARK: - Library

    var catalog: [DockWidgetDescriptor] {
        BuiltInDockWidgets.all.map(Self.descriptor(of:)) + installed.map(Self.descriptor(of:))
    }

    func descriptor(id: String) -> DockWidgetDescriptor? {
        if id.hasPrefix(DockWidgetManifest.reservedPrefix) {
            return BuiltInDockWidgets.widget(id: id).map(Self.descriptor(of:))
        }
        return installed.first { $0.id == id }.map(Self.descriptor(of:))
    }

    private static func descriptor(of widget: BuiltInDockWidget) -> DockWidgetDescriptor {
        DockWidgetDescriptor(
            id: widget.id, metadata: widget.metadata, preferences: widget.preferences, isBuiltIn: true)
    }

    private static func descriptor(of install: DockWidgetInstall) -> DockWidgetDescriptor {
        let manifest = install.manifest
        return DockWidgetDescriptor(
            id: install.id,
            metadata: DockWidgetMetadata(
                name: manifest.name, subtitle: manifest.subtitle, icon: manifest.icon,
                category: manifest.category, sizes: manifest.sizes.map(\.widgetSize)),
            preferences: manifest.preferences ?? [], isBuiltIn: false)
    }

    // MARK: - Instances

    /// An unset preference reads as its default, through `DockWidgetPreferences` and the editor.
    func registerDefaults(for instanceID: UUID, widgetID: String) {
        widgetIDs[instanceID] = widgetID
        guard let descriptor = descriptor(id: widgetID) else { return }
        var defaults: [String: Any] = [:]
        for preference in descriptor.preferences {
            guard let value = preference.registeredDefault else { continue }
            defaults[Self.key(instanceID, preference.name)] = value
        }
        UserDefaults.standard.register(defaults: defaults)
    }

    /// Releases the instance's widget object and deletes every value stored for it.
    func removeInstance(_ instanceID: UUID) {
        retire { id, _ in id == instanceID }
        widgetIDs[instanceID] = nil
        instanceFailures[instanceID] = nil
        let prefix = Self.key(instanceID, "")
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// The instance's object, made on first ask; nil while loading or failed. Observes builds.
    func widget(for instanceID: UUID, widgetID: String) -> (any OnecastDockWidget)? {
        if widgetIDs[instanceID] != widgetID { registerDefaults(for: instanceID, widgetID: widgetID) }
        let isBuiltIn = widgetID.hasPrefix(DockWidgetManifest.reservedPrefix)
        let build = isBuiltIn ? nil : builds[widgetID]
        if !isBuiltIn && !isThirdPartyEnabled { return nil }
        if let existing = live[instanceID], existing.widgetID == widgetID { return existing.widget }

        let made: (any OnecastDockWidget)?
        if isBuiltIn {
            made = BuiltInDockWidgets.widget(id: widgetID)?.make()
        } else {
            guard case .ready(let factory)? = build else { return nil }
            made = factory.make()
            if made == nil {
                instanceFailures[instanceID] = PluginLoadError.wrongType(
                    name: factory.name, protocolName: PluginSourceKind.dockWidget.protocolName
                ).localizedDescription
            }
        }
        guard let made else { return nil }
        instanceFailures[instanceID] = nil
        live[instanceID] = LiveWidget(widgetID: widgetID, widget: made)
        return made
    }

    func state(for instanceID: UUID) -> DockWidgetInstanceState {
        guard let widgetID = widgetIDs[instanceID] else { return .loading }
        if let failure = instanceFailures[instanceID] { return .failed(failure) }
        return state(forWidgetID: widgetID)
    }

    func state(forWidgetID widgetID: String) -> DockWidgetInstanceState {
        if widgetID.hasPrefix(DockWidgetManifest.reservedPrefix) {
            return BuiltInDockWidgets.widget(id: widgetID) == nil
                ? .failed("This widget is no longer part of Onecast.") : .ready
        }
        guard isThirdPartyEnabled else { return .unavailable }
        guard hasScanned else { return .loading }
        guard installed.contains(where: { $0.id == widgetID }) else {
            return .failed("“\(widgetID)” isn't in the DockWidgets folder.")
        }
        switch builds[widgetID] {
        case .ready?: return .ready
        case .failed(let message)?: return .failed(message)
        case nil: return .loading
        }
    }

    /// The widget's popover, or nil when it has none or is not running.
    func popoverView(
        instanceID: UUID, reference: DockWidgetReference, edge: DockEdge, tileLength: CGFloat
    ) -> AnyView? {
        guard let widget = widget(for: instanceID, widgetID: reference.widgetID) else { return nil }
        return widget.popover(
            context: context(
                instanceID: instanceID, span: reference.span, edge: edge, tileLength: tileLength))
    }

    func context(
        instanceID: UUID, span: DockWidgetSpan, edge: DockEdge, tileLength: CGFloat
    ) -> DockWidgetContext {
        DockWidgetContext(
            instanceID: instanceID.uuidString, size: span.widgetSize, edge: edge.widgetEdge,
            tileLength: tileLength,
            preferences: DockWidgetPreferences(instanceID: instanceID.uuidString),
            actions: actions(for: instanceID))
    }

    /// The editor wrote a preference; every tile re-asks its widget, which reads the value afresh.
    func preferencesDidChange() {
        preferencesRevision &+= 1
    }

    private static func key(_ instanceID: UUID, _ name: String) -> String {
        DockWidgetPreferences.key(instanceID: instanceID.uuidString, name: name)
    }

    /// Calls `didRemove()` on, and forgets, every live object `matches` accepts.
    private func retire(_ matches: (UUID, LiveWidget) -> Bool) {
        for (instanceID, entry) in live where matches(instanceID, entry) {
            entry.widget.didRemove()
            live[instanceID] = nil
        }
    }

    // MARK: - Actions

    private func actions(for instanceID: UUID) -> DockWidgetActions {
        DockWidgetActions(
            openURL: { url in NSWorkspace.shared.open(url) },
            launchApp: { bundleID in DockWidgetManager.launchApp(bundleID: bundleID) },
            runShortcut: { name in DockWidgetManager.runShortcut(named: name) },
            closePopover: { [weak self] in self?.onClosePopover?(instanceID) },
            openSettings: { AppCore.shared.settingsCoordinator.showSettings(tab: .docks) })
    }

    private static func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            AppCore.shared.showMessage("No app with the identifier \(bundleID)", tone: .danger)
            return
        }
        AppLauncher.launch(url)
    }

    /// Through the Apple Shortcuts coordinator, so its feature switch still gates the run.
    private static func runShortcut(named name: String) {
        let core = AppCore.shared
        guard core.settings.appleShortcutsEnabled else {
            core.showMessage("Turn on Apple Shortcuts in Settings to run “\(name)”", tone: .danger)
            return
        }
        let match = core.appleShortcutCoordinator.entries.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard let id = match.flatMap({ AppleShortcut.id(fromEntryID: $0.id) }) else {
            core.showMessage("No shortcut named “\(name)”", tone: .danger)
            return
        }
        core.appleShortcutCoordinator.run(id: id)
    }

    // MARK: - Scanning and building

    func refresh() {
        guard isThirdPartyEnabled else { return }
        scanGeneration &+= 1
        let generation = scanGeneration
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) { DockWidgetCatalog.scan() }.value
            guard let self, self.isThirdPartyEnabled, generation == self.scanGeneration else { return }
            self.apply(found)
        }
    }

    private func apply(_ found: [DockWidgetInstall]) {
        let vanished = Set(installed.map(\.id)).subtracting(found.map(\.id))
        if found != installed { installed = found }
        hasScanned = true
        for id in vanished {
            retire { _, entry in entry.widgetID == id }
            builds[id] = nil
            requested[id] = nil
        }
        buildQueue.removeAll { queued in vanished.contains(queued.id) }
        for (instanceID, widgetID) in widgetIDs { registerDefaults(for: instanceID, widgetID: widgetID) }
        for install in found {
            if requested[install.id] == install.sourceHash, !isFailed(install.id) { continue }
            requested[install.id] = install.sourceHash
            enqueue(install)
        }
        armWatcher()
    }

    private func isFailed(_ widgetID: String) -> Bool {
        if case .failed? = builds[widgetID] { return true }
        return false
    }

    /// One compile at a time, so a folder of widgets never launches a swarm of `swiftc` processes.
    private func enqueue(_ install: DockWidgetInstall) {
        buildQueue.removeAll { $0.id == install.id }
        buildQueue.append(install)
        guard !isBuilding else { return }
        isBuilding = true
        Task { await drainBuildQueue() }
    }

    private func drainBuildQueue() async {
        while !buildQueue.isEmpty {
            let install = buildQueue.removeFirst()
            let result = await Task.detached(priority: .utility) {
                PluginBuilder.buildResult(install)
            }.value
            finishBuild(install, result)
        }
        isBuilding = false
    }

    /// A rebuild replaces the live objects, so tiles pick up the new code; preferences persist.
    private func finishBuild(_ install: DockWidgetInstall, _ result: Result<URL, PluginBuildError>) {
        guard isThirdPartyEnabled, requested[install.id] == install.sourceHash else { return }
        let outcome: Build
        switch result {
        case .failure(let error):
            outcome = .failed(error.localizedDescription)
        case .success(let dylib):
            do {
                outcome = .ready(try PluginLoader.dockWidgetFactory(install, builtDylib: dylib))
            } catch {
                outcome = .failed(error.localizedDescription)
            }
        }
        retire { _, entry in entry.widgetID == install.id }
        for instanceID in widgetIDs.filter({ $0.value == install.id }).keys {
            instanceFailures[instanceID] = nil
        }
        builds[install.id] = outcome
    }

    func uninstall(_ install: DockWidgetInstall) {
        try? FileManager.default.removeItem(at: install.directory)
        refresh()
    }

    // MARK: - Live install detection

    /// Watches the folder and each widget's files, so a save while Onecast runs rebuilds it.
    private func armWatcher() {
        let watcher = watcher ?? DockWidgetFolderWatcher { [weak self] in self?.scheduleRescan() }
        self.watcher = watcher
        watcher.watch(DockWidgetFolderWatcher.paths(root: DockWidgetCatalog.widgetsDirectory(), installs: installed))
    }

    private func scheduleRescan() {
        guard isThirdPartyEnabled else { return }
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            self.refresh()
        }
    }

    private func stopWatching() {
        scanGeneration &+= 1
        rescanTask?.cancel()
        rescanTask = nil
        watcher?.stop()
        watcher = nil
    }
}

/// File sources over the folder and each widget's files; a directory source misses in-place saves.
@MainActor
private final class DockWidgetFolderWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    static func paths(root: URL, installs: [DockWidgetInstall]) -> [URL] {
        var urls = [root]
        for install in installs {
            urls.append(install.directory)
            urls.append(install.directory.appendingPathComponent("manifest.json"))
            for source in install.sources {
                urls.append(source)
                var parent = source.deletingLastPathComponent()
                while parent.path.count > install.directory.path.count {
                    urls.append(parent)
                    parent = parent.deletingLastPathComponent()
                }
            }
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    /// Replaces the watched set; an atomic save swaps the file's inode, so every rescan re-arms.
    func watch(_ urls: [URL]) {
        stop()
        for url in urls {
            let descriptor = Darwin.open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
                queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.onChange() }
            }
            source.setCancelHandler { Darwin.close(descriptor) }
            sources.append(source)
            source.resume()
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources = []
    }
}
