import AppKit
import OSLog

/// Reads, rewrites and hides the macOS Dock through its own `com.apple.dock` preferences.
@MainActor
final class NativeDockService {
    /// Fires with the Dock's pinned apps when someone other than Onecast rearranges them.
    var onNativeLayoutChanged: (([NativeDockTile]) -> Void)?

    private struct AppliedLayout {
        var id: UUID
        var signature: [String]
    }

    private struct FileStamp: Equatable {
        var inode: UInt64
        var seconds: Int
        var nanoseconds: Int
        var size: Int64
    }

    private static let dockDomain = "com.apple.dock"
    private static let layoutKey = "persistent-apps"
    private static let orientationKey = "orientation"
    private static let autohideKey = "autohide"
    private static let autohideDelayKey = "autohide-delay"
    private static let autohideTimeModifierKey = "autohide-time-modifier"
    private static let sentinelName = "native-dock-hiding.json"
    /// The Dock rewrites its preferences for a moment after it relaunches.
    private static let ownWriteWindow = Duration.seconds(4)
    private static let settleDelay = Duration.milliseconds(300)
    private static let terminationWait: TimeInterval = 2
    private static let restartWait: TimeInterval = 5
    private nonisolated static let logger = Logger(subsystem: "com.onecast", category: "NativeDock")

    private lazy var sentinelURL = AppPaths.applicationSupport()
        .appending(path: Self.sentinelName, directoryHint: .notDirectory)
    private var originals: NativeDockHidingPlan.Settings?
    private var loadedOriginals = false

    private var lastApplied: AppliedLayout?
    private var restartTask: Task<Void, Never>?
    private var restartRequested = false

    private var directorySource: DispatchSourceFileSystemObject?
    private var settleTask: Task<Void, Never>?
    private var observedSignature: [String]?
    private var preferencesStamp: FileStamp?
    private var ownWritesUntil = ContinuousClock.now

    isolated deinit {
        directorySource?.cancel()
        settleTask?.cancel()
    }

    // MARK: - Layout

    /// The layout last applied, only while the Dock still shows it.
    var lastAppliedLayoutID: UUID? {
        guard let lastApplied, let tiles = try? readCurrentLayout(),
            NativeDockPlist.signature(of: tiles) == lastApplied.signature
        else { return nil }
        return lastApplied.id
    }

    var macOSDockEdge: DockEdge {
        (Self.value(for: Self.orientationKey) as? String).flatMap(DockEdge.init(rawValue:)) ?? .bottom
    }

    func readCurrentLayout() throws -> [NativeDockTile] {
        Self.synchronize()
        guard let tiles = NativeDockPlist.tiles(fromPreference: Self.value(for: Self.layoutKey)) else {
            throw NativeDockError.unreadableLayout
        }
        return tiles
    }

    /// Validates, writes `persistent-apps`, and restarts the Dock unless it already shows them.
    func apply(_ tiles: [NativeDockTile], layoutID: UUID?) throws {
        let resolution = NativeDockPlist.resolve(tiles) { bundleID, path in
            Self.location(ofApp: bundleID, savedPath: path)
        }
        if !resolution.missingApps.isEmpty { throw NativeDockError.missingApps(resolution.missingApps) }
        if !resolution.unwritable.isEmpty { throw NativeDockError.unwritableTiles(resolution.unwritable) }

        let written = NativeDockPlist.tiles(fromPreference: resolution.dictionaries) ?? []
        let signature = NativeDockPlist.signature(of: written)
        lastApplied = layoutID.map { AppliedLayout(id: $0, signature: signature) }
        if let current = try? readCurrentLayout(), NativeDockPlist.signature(of: current) == signature {
            return
        }
        Self.set(resolution.dictionaries as NSArray, for: Self.layoutKey)
        guard Self.synchronize() else {
            lastApplied = nil
            throw NativeDockError.writeFailed
        }
        observedSignature = signature
        ownWritesUntil = .now + Self.ownWriteWindow
        restartDock()
    }

    /// The pinned app's current path: where it was saved, else wherever its bundle ID resolves.
    private static func location(ofApp bundleID: String?, savedPath: String) -> String? {
        if FileManager.default.fileExists(atPath: savedPath) { return savedPath }
        guard let bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return url.path
    }

    // MARK: - Hiding

    /// A sentinel left by a run that never got to give the Dock back is honoured at launch.
    func recoverAfterCrash() {
        guard let saved = savedOriginals() else { return }
        if commit(hidden: false, hiding: .reachable, saved: saved) { restartDock() }
    }

    /// Idempotent; touches the preferences only when a value has to change.
    func applyHiding(hidden: Bool, hiding: NativeDockHiding) {
        let saved = savedOriginals()
        guard hidden || saved != nil else { return }
        if commit(hidden: hidden, hiding: hiding, saved: saved) { restartDock() }
    }

    /// Blocks, briefly, so the Dock is back as the user had it before the process exits.
    func restoreForTermination() {
        setObservingChanges(false)
        guard let saved = savedOriginals() else { return }
        if commit(hidden: false, hiding: .reachable, saved: saved) {
            Self.killDock(timeout: Self.terminationWait)
        }
    }

    /// Writes one hiding step and says whether the Dock has to restart to show it.
    private func commit(
        hidden: Bool, hiding: NativeDockHiding, saved: NativeDockHidingPlan.Settings?
    ) -> Bool {
        let step = NativeDockHidingPlan.step(
            hidden: hidden, hiding: hiding, current: Self.hidingSettings(), saved: saved)
        if let held = step.originals, held != saved, !persist(held) {
            Self.logger.error("Left the macOS Dock alone: its original settings could not be saved")
            return false
        }
        Self.write(step.edits)
        guard step.edits.isEmpty || Self.synchronize() else {
            Self.logger.error("The macOS Dock's hiding settings could not be written")
            return false
        }
        if step.originals == nil { discardOriginals() }
        guard step.restartsDock else { return false }
        ownWritesUntil = .now + Self.ownWriteWindow
        return true
    }

    private static func hidingSettings() -> NativeDockHidingPlan.Settings {
        NativeDockHidingPlan.Settings(
            autohide: (value(for: autohideKey) as? NSNumber)?.boolValue,
            autohideDelay: (value(for: autohideDelayKey) as? NSNumber)?.doubleValue,
            autohideTimeModifier: (value(for: autohideTimeModifierKey) as? NSNumber)?.doubleValue)
    }

    private static func write(_ edits: NativeDockHidingPlan.Edits) {
        write(edits.autohide, key: autohideKey) { NSNumber(value: $0) }
        write(edits.autohideDelay, key: autohideDelayKey) { NSNumber(value: $0) }
        write(edits.autohideTimeModifier, key: autohideTimeModifierKey) { NSNumber(value: $0) }
    }

    private static func write<Value>(
        _ change: NativeDockHidingPlan.Change<Value>?, key: String, as object: (Value) -> NSNumber
    ) {
        switch change {
        case .set(let value): set(object(value), for: key)
        case .remove: set(nil, for: key)
        case nil: break
        }
    }

    // MARK: - Sentinel

    /// Loaded once; the file is the record that the Dock is still hidden by a past run.
    private func savedOriginals() -> NativeDockHidingPlan.Settings? {
        guard !loadedOriginals else { return originals }
        loadedOriginals = true
        guard let data = try? Data(contentsOf: sentinelURL) else { return nil }
        do {
            originals = try JSONDecoder().decode(NativeDockHidingPlan.Settings.self, from: data)
        } catch {
            let reason = error.localizedDescription
            Self.logger.error("The Dock sentinel is unreadable: \(reason, privacy: .public)")
        }
        return originals
    }

    private func persist(_ settings: NativeDockHidingPlan.Settings) -> Bool {
        do {
            try JSONEncoder().encode(settings).write(to: sentinelURL, options: .atomic)
            originals = settings
            return true
        } catch {
            let reason = error.localizedDescription
            Self.logger.error("The Dock sentinel could not be written: \(reason, privacy: .public)")
            return false
        }
    }

    private func discardOriginals() {
        originals = nil
        try? FileManager.default.removeItem(at: sentinelURL)
    }

    // MARK: - Restarting

    /// Requests coalesce: writes made while one restart is running earn exactly one more.
    private func restartDock() {
        restartRequested = true
        guard restartTask == nil else { return }
        let wait = Self.restartWait
        restartTask = Task { [weak self] in
            while let self, self.restartRequested {
                self.restartRequested = false
                await Task.detached { Self.killDock(timeout: wait) }.value
            }
            self?.restartTask = nil
        }
    }

    /// Launchd relaunches the Dock, which re-reads its preferences; the exit status is no signal.
    private nonisolated static func killDock(timeout: TimeInterval) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // `ProcessExit.wait` has no timeout, and the quit path must not hang on a stuck child.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            logger.error("killall Dock failed to start: \(error.localizedDescription, privacy: .public)")
            return
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut { process.terminate() }
    }

    // MARK: - Observing

    func setObservingChanges(_ on: Bool) {
        guard on != (directorySource != nil) else { return }
        if on { startObserving() } else { stopObserving() }
    }

    /// The preferences file is replaced atomically, so the folder is watched rather than the file.
    private func startObserving() {
        let descriptor = Darwin.open(Self.preferencesFolder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Self.logger.error("The preferences folder could not be watched")
            return
        }
        observedSignature = (try? readCurrentLayout()).map(NativeDockPlist.signature(of:))
        preferencesStamp = Self.stamp(of: Self.preferencesFile)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.preferencesFolderDidChange() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        directorySource = source
        source.resume()
    }

    private func stopObserving() {
        settleTask?.cancel()
        settleTask = nil
        directorySource?.cancel()
        directorySource = nil
        observedSignature = nil
        preferencesStamp = nil
    }

    /// Every app's preferences live in this folder, so a burst of writes settles into one look.
    private func preferencesFolderDidChange() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.settleDelay)
            } catch {
                return
            }
            self?.reloadObservedLayout()
        }
    }

    private func reloadObservedLayout() {
        guard directorySource != nil else { return }
        let stamp = Self.stamp(of: Self.preferencesFile)
        guard stamp != preferencesStamp else { return }
        preferencesStamp = stamp
        guard let tiles = try? readCurrentLayout() else { return }
        let signature = NativeDockPlist.signature(of: tiles)
        guard signature != observedSignature else { return }
        observedSignature = signature
        guard ContinuousClock.now >= ownWritesUntil else { return }
        onNativeLayoutChanged?(tiles)
    }

    private static var preferencesFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences", directoryHint: .isDirectory)
    }

    private static var preferencesFile: URL {
        preferencesFolder.appending(path: "\(dockDomain).plist", directoryHint: .notDirectory)
    }

    private nonisolated static func stamp(of url: URL) -> FileStamp? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return FileStamp(
            inode: info.st_ino, seconds: info.st_mtimespec.tv_sec,
            nanoseconds: info.st_mtimespec.tv_nsec, size: info.st_size)
    }

    // MARK: - Preferences

    private static func value(for key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, dockDomain as CFString)
    }

    private static func set(_ value: CFPropertyList?, for key: String) {
        CFPreferencesSetAppValue(key as CFString, value, dockDomain as CFString)
    }

    @discardableResult
    private static func synchronize() -> Bool {
        CFPreferencesAppSynchronize(dockDomain as CFString)
    }
}
