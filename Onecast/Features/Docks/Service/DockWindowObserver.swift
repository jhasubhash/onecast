import AppKit
@preconcurrency import ApplicationServices

/// What the macOS Dock knows and custom docks do not: minimized windows and badges.
@MainActor
@Observable
final class DockWindowObserver {
    private static let badgeInterval = Duration.seconds(3)
    private static let previewInterval = Duration.seconds(4)
    /// A focus flip-flop must not turn into a capture per flip.
    private static let previewMinimumGap = Duration.seconds(2)
    private static let attachAttempts = 5
    private static let attachRetry = Duration.milliseconds(600)
    private static let accessibilityChanged = Notification.Name("com.apple.accessibility.api")

    /// Oldest minimize first, as the macOS Dock lays its minimized windows out.
    private(set) var minimized: [DockMinimizedWindow] = []
    /// Bundle ID → the label the macOS Dock draws as that app's badge.
    private(set) var badges: [String: String] = [:]
    /// Read by `preview(for:)` so a view refreshes when a snapshot lands for a tile it shows.
    private var previewRevision = 0

    private struct Tracked {
        let token: String
        let pid: pid_t
        let sequence: Int
        var element: AXUIElement
        var title: String
        var isMinimized: Bool
        var minimizedAt: Date?
    }

    private struct AppInfo {
        let name: String
        let bundleID: String?
        let path: String
    }

    @ObservationIgnored private var wantsMinimized = false
    @ObservationIgnored private var wantsBadges = false
    @ObservationIgnored private var isTrackingWindows = false
    @ObservationIgnored private var trustToken: NotificationToken?
    @ObservationIgnored private var workspaceTokens: [NotificationToken] = []

    @ObservationIgnored private var tracked: [String: Tracked] = [:]
    @ObservationIgnored private var apps: [pid_t: AppInfo] = [:]
    @ObservationIgnored private var observers: [pid_t: DockAppObserver] = [:]
    @ObservationIgnored private var attaching: Set<pid_t> = []
    @ObservationIgnored private var attachTasks: [pid_t: Task<Void, Never>] = [:]
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var seedTask: Task<Void, Never>?

    @ObservationIgnored private let previews = DockPreviewStore()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var focusTask: Task<Void, Never>?
    @ObservationIgnored private var focusedToken: String?
    @ObservationIgnored private var capturing: Set<String> = []
    @ObservationIgnored private var lastCapture: [String: ContinuousClock.Instant] = [:]
    /// Tokens already looked up on disk, so a window with no saved snapshot is not re-read.
    @ObservationIgnored private var lookedUp: Set<String> = []

    @ObservationIgnored private var badgeTask: Task<Void, Never>?

    // MARK: - Switches

    /// Idempotent. Each half runs only while asked for, and only with Accessibility granted.
    func setActive(minimizedWindows: Bool, badges: Bool) {
        wantsMinimized = minimizedWindows
        wantsBadges = badges
        reconcile()
    }

    private func reconcile() {
        guard wantsMinimized || wantsBadges else {
            stopTrackingWindows()
            stopBadges()
            trustToken = nil
            return
        }
        if trustToken == nil { observeTrust() }
        guard Permissions.isAccessibilityTrusted() else {
            stopTrackingWindows()
            stopBadges()
            return
        }
        if wantsMinimized { startTrackingWindows() } else { stopTrackingWindows() }
        if wantsBadges { startBadges() } else { stopBadges() }
    }

    /// The grant can arrive or leave while a switch is on, and nothing else says so.
    private func observeTrust() {
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(
            forName: Self.accessibilityChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        trustToken = NotificationToken(observer, center: center)
    }

    // MARK: - Actions

    /// Nil without a snapshot; reads a revision so a view refreshes when one lands.
    func preview(for token: String) -> NSImage? {
        _ = previewRevision
        return previews.image(for: token)
    }

    /// Un-minimizes the window and brings it forward; macOS follows it to its Space on activation.
    func restore(_ token: String) {
        guard let entry = tracked[token] else { return }
        let element = entry.element
        let pid = entry.pid
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                DockWindowAccess.bringForward(element, pid: pid)
            }.value
            self?.restored(token, outcome)
        }
    }

    @discardableResult
    func minimizeFocusedWindow(of bundleID: String) -> Bool {
        guard Permissions.isAccessibilityTrusted(),
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { !$0.isTerminated })
        else { return false }
        return DockWindowAccess.minimizeFocusedWindow(of: app.processIdentifier)
    }

    private func restored(_ token: String, _ outcome: DockWindowAccess.Restoration) {
        switch outcome {
        case .restored: setMinimized(false, token: token)
        case .gone: forget(token)
        case .failed: break
        }
    }

    // MARK: - Windows

    private func startTrackingWindows() {
        guard !isTrackingWindows else { return }
        isTrackingWindows = true
        workspaceTokens = [
            observeWorkspace(NSWorkspace.didLaunchApplicationNotification) { [weak self] pid in
                self?.attachInBackground(pid: pid)
            },
            observeWorkspace(NSWorkspace.didTerminateApplicationNotification) { [weak self] pid in
                self?.detach(pid: pid)
            },
            observeWorkspace(NSWorkspace.didActivateApplicationNotification) { [weak self] pid in
                self?.attachInBackground(pid: pid)
                self?.refreshFocus()
            }
        ]
        seedTask = Task { [weak self] in
            await self?.seed()
        }
        previewTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.previewInterval)
                self?.previewTick()
            }
        }
    }

    private func stopTrackingWindows() {
        guard isTrackingWindows else { return }
        isTrackingWindows = false
        workspaceTokens = []
        seedTask?.cancel()
        seedTask = nil
        previewTask?.cancel()
        previewTask = nil
        focusTask?.cancel()
        focusTask = nil
        for task in attachTasks.values { task.cancel() }
        attachTasks = [:]
        attaching = []
        for observer in observers.values { observer.invalidate() }
        observers = [:]
        apps = [:]
        tracked = [:]
        focusedToken = nil
        capturing = []
        lastCapture = [:]
        lookedUp = []
        if !minimized.isEmpty { minimized = [] }
        previews.evictAll()
    }

    private func observeWorkspace(
        _ name: Notification.Name, handler: @escaping @MainActor (pid_t) -> Void
    ) -> NotificationToken {
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            let pid = app.processIdentifier
            Task { @MainActor in handler(pid) }
        }
        return NotificationToken(observer, center: center)
    }

    /// One sweep of what is already running; later apps arrive through the workspace.
    private func seed() async {
        for app in WindowInventory.candidates() {
            guard !Task.isCancelled else { return }
            await attach(app)
        }
        let live = Set(tracked.keys)
        Task.detached(priority: .utility) { DockPreviewStore.purge(keeping: live) }
    }

    private func attachInBackground(pid: pid_t) {
        guard isTrackingWindows, observers[pid] == nil, attachTasks[pid] == nil,
            let app = NSRunningApplication(processIdentifier: pid)
        else { return }
        attachTasks[pid] = Task { [weak self] in
            await self?.attach(app)
            self?.attachTasks[pid] = nil
        }
    }

    /// Observes the app and reads its windows, retrying while a young app is not yet ready.
    private func attach(_ app: NSRunningApplication) async {
        let pid = app.processIdentifier
        guard isTrackingWindows, observers[pid] == nil, !attaching.contains(pid),
            app.activationPolicy == .regular, !app.isTerminated,
            pid != NSRunningApplication.current.processIdentifier
        else { return }
        attaching.insert(pid)
        defer { attaching.remove(pid) }
        apps[pid] = AppInfo(
            name: app.localizedName ?? app.bundleIdentifier ?? "",
            bundleID: app.bundleIdentifier, path: app.bundleURL?.path ?? "")

        let handler: @Sendable (DockAppObserver.Event) -> Void = { [weak self] event in
            Task { @MainActor in self?.handle(event, pid: pid) }
        }
        for attempt in 0..<Self.attachAttempts {
            if attempt > 0 { try? await Task.sleep(for: Self.attachRetry) }
            guard isTrackingWindows, !Task.isCancelled else { return }
            let attached = await Task.detached(priority: .utility) {
                Self.observe(pid: pid, handler: handler)
            }.value
            if let attached {
                adopt(attached.observer, windows: attached.windows, pid: pid)
                return
            }
        }
        apps[pid] = nil
    }

    private nonisolated static func observe(
        pid: pid_t, handler: @escaping @Sendable (DockAppObserver.Event) -> Void
    ) -> (observer: DockAppObserver, windows: [DockWindowAccess.Window])? {
        guard let observer = DockAppObserver.attach(pid: pid, handler: handler) else { return nil }
        let windows = DockWindowAccess.windows(of: pid)
        for window in windows { observer.watch(window.element) }
        return (observer, windows)
    }

    private func adopt(
        _ observer: DockAppObserver, windows: [DockWindowAccess.Window], pid: pid_t
    ) {
        guard isTrackingWindows, observers[pid] == nil else {
            observer.invalidate()
            return
        }
        observers[pid] = observer
        for window in windows { track(window, pid: pid) }
        publishMinimized()
    }

    private func detach(pid: pid_t) {
        attachTasks[pid]?.cancel()
        attachTasks[pid] = nil
        observers.removeValue(forKey: pid)?.invalidate()
        for token in tracked.values.filter({ $0.pid == pid }).map(\.token) {
            drop(token)
        }
        apps[pid] = nil
        publishMinimized()
    }

    private func handle(_ event: DockAppObserver.Event, pid: pid_t) {
        guard isTrackingWindows, apps[pid] != nil else { return }
        switch event {
        case .windowCreated(let element):
            learn(element, pid: pid)
        case .focusedWindowChanged:
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { refreshFocus() }
        case .minimized(let element):
            guard let token = token(of: element, pid: pid) else { return learn(element, pid: pid) }
            setMinimized(true, token: token)
        case .restored(let element):
            guard let token = token(of: element, pid: pid) else { return learn(element, pid: pid) }
            setMinimized(false, token: token)
        case .destroyed(let element):
            if let token = token(of: element, pid: pid) { forget(token) }
        }
    }

    /// A window the sweep never saw: read it off the main actor, then start watching it.
    private func learn(_ element: AXUIElement, pid: pid_t) {
        let observer = observers[pid]
        Task { [weak self] in
            let window = await Task.detached(priority: .utility) { () -> DockWindowAccess.Window? in
                guard let window = DockWindowAccess.window(element) else { return nil }
                observer?.watch(element)
                return window
            }.value
            guard let window, let self, isTrackingWindows, apps[pid] != nil else { return }
            track(window, pid: pid)
            publishMinimized()
        }
    }

    private func track(_ window: DockWindowAccess.Window, pid: pid_t) {
        let at: Date? = window.isMinimized ? Date() : nil
        if var existing = tracked[window.token] {
            existing.element = window.element
            existing.title = window.title
            if window.isMinimized != existing.isMinimized {
                existing.isMinimized = window.isMinimized
                existing.minimizedAt = at
            }
            tracked[window.token] = existing
            return
        }
        sequence += 1
        tracked[window.token] = Tracked(
            token: window.token, pid: pid, sequence: sequence, element: window.element,
            title: window.title, isMinimized: window.isMinimized, minimizedAt: at)
    }

    private func token(of element: AXUIElement, pid: pid_t) -> String? {
        tracked.values.first { $0.pid == pid && CFEqual($0.element, element) }?.token
    }

    private func setMinimized(_ isMinimized: Bool, token: String) {
        guard var entry = tracked[token], entry.isMinimized != isMinimized else { return }
        entry.isMinimized = isMinimized
        entry.minimizedAt = isMinimized ? Date() : nil
        tracked[token] = entry
        publishMinimized()
        if isMinimized { refreshTitle(of: token) }
    }

    /// A window is retitled while it is up, so the minimized tile reads the title it left with.
    private func refreshTitle(of token: String) {
        guard let element = tracked[token]?.element else { return }
        Task { [weak self] in
            let title = await Task.detached(priority: .utility) {
                DockWindowAccess.title(of: element)
            }.value
            guard let self, var entry = tracked[token], entry.title != title else { return }
            entry.title = title
            tracked[token] = entry
            publishMinimized()
        }
    }

    private func forget(_ token: String) {
        drop(token)
        publishMinimized()
    }

    private func drop(_ token: String) {
        tracked[token] = nil
        lastCapture[token] = nil
        lookedUp.remove(token)
        if focusedToken == token { focusedToken = nil }
        previews.evict(token)
    }

    private func publishMinimized() {
        let next = tracked.values.filter(\.isMinimized)
            .sorted {
                ($0.minimizedAt ?? .distantPast, $0.sequence)
                    < ($1.minimizedAt ?? .distantPast, $1.sequence)
            }
            .compactMap { entry -> DockMinimizedWindow? in
                guard let app = apps[entry.pid] else { return nil }
                return DockMinimizedWindow(
                    token: entry.token, title: entry.title, appName: app.name,
                    bundleID: app.bundleID, appPath: app.path)
            }
        if next != minimized { minimized = next }
        loadSavedPreviews(for: next.map(\.token))
    }

    // MARK: - Previews

    private var canPreview: Bool { isTrackingWindows && Permissions.isScreenRecordingTrusted() }

    private func previewTick() {
        guard canPreview else { return }
        if let focusedToken { capture(focusedToken) } else { refreshFocus() }
    }

    /// The frontmost app's focused window is the one worth a snapshot: it is about to be minimized.
    private func refreshFocus() {
        guard canPreview, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            observers[pid] != nil
        else {
            focusedToken = nil
            return
        }
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            let token = await Task.detached(priority: .utility) {
                DockWindowAccess.focusedWindowToken(of: pid)
            }.value
            guard !Task.isCancelled, let self else { return }
            focusedToken = token
            if let token { capture(token) }
        }
    }

    private func capture(_ token: String) {
        guard canPreview, tracked[token]?.isMinimized == false, !capturing.contains(token),
            let windowID = CGWindowID(token)
        else { return }
        let now = ContinuousClock.now
        if let last = lastCapture[token], now - last < Self.previewMinimumGap { return }
        lastCapture[token] = now
        capturing.insert(token)
        Task { [weak self] in
            let png = await Task.detached(priority: .utility) { () -> Data? in
                guard let png = await DockPreviewStore.capture(windowID: windowID) else {
                    return nil
                }
                DockPreviewStore.persist(png, for: token)
                return png
            }.value
            self?.captured(png, for: token)
        }
    }

    private func captured(_ png: Data?, for token: String) {
        capturing.remove(token)
        guard let png else { return }
        // The window closed, or the switch went off, while the capture ran: drop what it wrote.
        guard isTrackingWindows, tracked[token] != nil else { return previews.evict(token) }
        guard previews.insert(png, for: token) else { return }
        if tracked[token]?.isMinimized == true { previewRevision += 1 }
    }

    /// After a restart the snapshots on disk are all a minimized window has.
    private func loadSavedPreviews(for tokens: [String]) {
        let missing = tokens.filter { previews.image(for: $0) == nil && !lookedUp.contains($0) }
        guard !missing.isEmpty else { return }
        lookedUp.formUnion(missing)
        Task { [weak self] in
            let saved = await Task.detached(priority: .utility) { DockPreviewStore.load(missing) }
                .value
            guard let self, isTrackingWindows else { return }
            var landed = false
            for (token, png) in saved where tracked[token] != nil {
                guard previews.image(for: token) == nil else { continue }
                landed = previews.insert(png, for: token) || landed
            }
            if landed { previewRevision += 1 }
        }
    }

    // MARK: - Badges

    private func startBadges() {
        guard badgeTask == nil else { return }
        badgeTask = Task { [weak self] in
            var resolved: [URL: String] = [:]
            while !Task.isCancelled {
                let known = resolved
                let reading = await Task.detached(priority: .utility) {
                    DockBadgeAccess.read(resolved: known)
                }.value
                if let reading {
                    resolved = reading.resolved
                    self?.publish(badges: reading.badges)
                }
                try? await Task.sleep(for: Self.badgeInterval)
            }
        }
    }

    private func stopBadges() {
        badgeTask?.cancel()
        badgeTask = nil
        if !badges.isEmpty { badges = [:] }
    }

    private func publish(badges next: [String: String]) {
        if next != badges { badges = next }
    }
}
