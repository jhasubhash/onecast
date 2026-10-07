import AppKit

/// Turns Presentation Mode on and off: the display mode, the presented window, every other app.
@MainActor
@Observable
final class PresentationCoordinator {
    enum Phase: Equatable {
        case idle, starting, presenting, stopping
    }

    /// A connected display and the modes its resolution picker offers.
    struct DisplayChoices: Identifiable {
        let id: CGDirectDisplayID
        let key: String
        let name: String
        let current: PresentationDisplayMode?
        let choices: [PresentationDisplayMode]
    }

    private(set) var phase: Phase = .idle
    private(set) var startedAt: Date?
    private(set) var presentedApp: NSRunningApplication?
    private(set) var displayName: String?
    /// The mode switched to, nil when the display kept its own.
    private(set) var resolution: PresentationDisplayMode?

    var isPresenting: Bool { phase == .presenting }
    var isBusy: Bool { phase == .starting || phase == .stopping }

    private let settings: AppSettings
    private let appIndex: AppIndex
    /// HUDs and dialogs only. Never state this type owns.
    private unowned let core: AppCore

    @ObservationIgnored private var session: PresentationSession?
    @ObservationIgnored private var originalMode: CGDisplayMode?
    @ObservationIgnored private var activationToken: NotificationToken?
    @ObservationIgnored private var screensToken: NotificationToken?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var pendingPresent: Task<Void, Never>?

    /// A just-launched app reports its window a moment after it activates.
    private static let windowWait: Duration = .milliseconds(200)
    private static let windowAttempts = 15

    init(settings: AppSettings, appIndex: AppIndex, core: AppCore) {
        self.settings = settings
        self.appIndex = appIndex
        self.core = core
    }

    func applyEnabled() {
        appIndex.setCommandsVisible(
            [.togglePresentation, .startPresentation, .stopPresentation],
            settings.presentationEnabled && settings.presentationShowInLauncher)
        if !settings.presentationEnabled, phase == .presenting { stop() }
    }

    func toggle() {
        switch phase {
        case .idle: start()
        case .presenting: stop()
        case .starting, .stopping: return
        }
    }

    func start() {
        if phase == .presenting { core.showMessage("Already presenting", tone: .neutral) }
        guard phase == .idle else { return }
        guard settings.presentationEnabled else {
            core.showMessage("Turn on Presentation Mode in Settings", tone: .danger)
            return
        }
        // Explicit user gesture, so prompting for the grant is right here.
        guard Permissions.ensureAccessibility() else {
            core.showMessage("Presentation Mode needs Accessibility access", tone: .danger)
            return
        }
        phase = .starting
        transition = Task { [weak self] in await self?.begin() }
    }

    func stop() {
        if phase == .idle { core.showMessage("Not presenting", tone: .neutral) }
        guard phase == .presenting else { return }
        phase = .stopping
        pendingPresent?.cancel()
        activationToken = nil
        screensToken = nil
        transition = Task { [weak self] in await self?.end() }
    }

    /// Sizes the presented window again; with none presented yet, adopts the app in front.
    func refit() {
        guard phase == .presenting, let session,
            let app = presentedApp ?? frontmostApp()
        else { return }
        presentedApp = app
        transition = Task { [weak self] in
            if self?.settings.presentationWindowSize != .fullScreen { await session.leaveFullScreen() }
            self?.present(app, in: session)
        }
    }

    // MARK: - Settings

    /// Read once per pane appearance or display change: copying every mode is not free.
    func displayChoices() -> [DisplayChoices] {
        PresentationDisplayAccess.displays().map { display in
            DisplayChoices(
                id: display.id, key: display.key, name: display.name,
                current: PresentationDisplayAccess.currentMode(of: display.id)
                    .map(PresentationDisplayAccess.model),
                choices: PresentationResolutionPolicy.choices(
                    from: PresentationDisplayAccess.modes(of: display.id)
                        .map(PresentationDisplayAccess.model)))
        }
    }

    /// Nil `id` keeps the display's own mode while presenting.
    func setResolution(_ id: String?, forDisplay key: String) {
        settings.presentationResolutions[key] = id
    }

    /// The system open panel; the one system surface Onecast keeps, since it is the file browser.
    func chooseIgnoredApps() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        let chosen = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        let added = chosen.filter { !settings.presentationIgnoredApps.contains($0) }
        settings.presentationIgnoredApps += Array(Set(added)).sorted()
    }

    func removeIgnoredApp(_ bundleID: String) {
        settings.presentationIgnoredApps.removeAll { $0 == bundleID }
    }

    /// Quitting mid-presentation: puts back what can be put back without waiting.
    func prepareForTermination() {
        guard let session else { return }
        if let originalMode { _ = PresentationDisplayAccess.set(originalMode, on: session.display) }
        session.restore(frames: false)
    }

    // MARK: - Starting

    private func begin() async {
        let target = frontmostApp().flatMap { isIgnored($0) ? nil : $0 }
        let display =
            target.flatMap(PresentationSession.display(of:))
            ?? NSScreen.underCursor.flatMap(PresentationDisplayAccess.displayID)
            ?? CGMainDisplayID()
        let session = PresentationSession(display: display)
        self.session = session
        runShortcut(named: settings.presentationStartShortcut)
        await switchResolution(of: display)

        putAwayOthers(except: target, in: session)
        if let target { present(target, in: session) }
        observe()
        displayName = PresentationDisplayAccess.screen(for: display)?.localizedName
        startedAt = Date()
        phase = .presenting
        core.showMessage(
            target == nil ? "Presenting: switch to the app to share" : "Presenting",
            tone: .neutral)
    }

    private func switchResolution(of display: CGDirectDisplayID) async {
        guard let key = PresentationDisplayAccess.screen(for: display)?.displayKey,
            let id = settings.presentationResolutions[key],
            let current = PresentationDisplayAccess.currentMode(of: display),
            PresentationDisplayAccess.model(of: current).id != id
        else { return }
        guard let mode = PresentationDisplayAccess.mode(id: id, on: display),
            PresentationDisplayAccess.set(mode, on: display)
        else {
            core.showMessage("Couldn’t change the display resolution", tone: .danger)
            return
        }
        originalMode = current
        resolution = PresentationDisplayAccess.model(of: mode)
        await PresentationDisplayAccess.settle(display, at: mode)
    }

    private func putAwayOthers(except target: NSRunningApplication?, in session: PresentationSession) {
        let style = settings.presentationOtherApps
        guard style != .leave else { return }
        for app in NSWorkspace.shared.runningApplications
        where isCandidate(app) && app != target {
            session.putAway(app, as: style)
        }
    }

    private func present(_ app: NSRunningApplication, in session: PresentationSession) {
        _ = session.present(
            app, size: settings.presentationWindowSize,
            marginPercent: settings.presentationMarginPercent)
    }

    // MARK: - While presenting

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        let activation = workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier else { return }
            Task { @MainActor [weak self] in self?.activated(pid: pid) }
        }
        activationToken = NotificationToken(activation, center: workspace)

        let screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.screensChanged() }
        }
        screensToken = NotificationToken(screens, center: .default)
    }

    private func activated(pid: pid_t) {
        guard phase == .presenting, let session,
            let app = NSRunningApplication(processIdentifier: pid), isCandidate(app),
            app != presentedApp
        else { return }
        let previous = presentedApp
        let behaviour = previous == nil ? .stack : settings.presentationAppSwitch
        guard behaviour != .ignore else { return }

        pendingPresent?.cancel()
        pendingPresent = Task { [weak self] in
            for _ in 0..<Self.windowAttempts {
                guard let self, !Task.isCancelled, self.phase == .presenting else { return }
                let presented = session.present(
                    app, size: self.settings.presentationWindowSize,
                    marginPercent: self.settings.presentationMarginPercent)
                if presented {
                    if behaviour == .replace, let previous {
                        session.putAway(previous, as: self.replacedStyle)
                    }
                    self.presentedApp = app
                    return
                }
                try? await Task.sleep(for: Self.windowWait)
            }
        }
    }

    /// Replace always puts the previous app away, even when other apps are otherwise left alone.
    private var replacedStyle: PresentationOtherApps {
        settings.presentationOtherApps == .minimize ? .minimize : .hide
    }

    private func screensChanged() {
        guard phase == .presenting, let session else { return }
        if PresentationDisplayAccess.screen(for: session.display) == nil {
            originalMode = nil
            stop()
        }
    }

    // MARK: - Ending

    private func end() async {
        if let session {
            await session.leaveFullScreen()
            if let originalMode, PresentationDisplayAccess.set(originalMode, on: session.display) {
                await PresentationDisplayAccess.settle(session.display, at: originalMode)
            }
            session.restore(frames: settings.presentationRestoresWindows)
        }
        runShortcut(named: settings.presentationEndShortcut)
        session = nil
        originalMode = nil
        presentedApp = nil
        displayName = nil
        resolution = nil
        startedAt = nil
        phase = .idle
        core.showMessage("Presentation ended", tone: .neutral)
    }

    // MARK: - Helpers

    private func frontmostApp() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication, isCandidate(app) else { return nil }
        return app
    }

    /// A regular app that is not Onecast and not on the leave-alone list.
    private func isCandidate(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && !app.isTerminated
            && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && !isIgnored(app)
    }

    private func isIgnored(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        return settings.presentationIgnoredApps.contains(bundleID)
    }

    private func runShortcut(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { [weak self] in
            do {
                try await AppleShortcutRunner.run(name: name)
            } catch {
                self?.core.showMessage("Couldn’t run the shortcut “\(name)”", tone: .danger)
            }
        }
    }
}
