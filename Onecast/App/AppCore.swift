import AppKit

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customCommands = CustomCommandStore()
    let quicklinks = QuicklinkStore()
    let windowLayouts = WindowLayoutStore()
    let customWindowSizes = CustomWindowSizeStore()
    let scheduledTasks = ScheduledTaskStore()
    let computerController = ComputerController()
    let clipboardStore = ClipboardStore()
    @ObservationIgnored private var clipboardTextIndexer: ClipboardTextIndexer?
    let clipboardManager: ClipboardManager
    let snippetsStore: SnippetsStore
    let snippetListener = SnippetKeywordListener(
        syntheticEventTag: Paster.onecastEventTag)
    let textInjector: TextInjector
    let hotKeys = HotKeyManager()
    let dictationAudioDucker = DictationAudioDucker()
    @ObservationIgnored private(set) lazy var dictationModels =
        DictationModelStore(idleRelease: settings.dictationIdleRelease)
    let hyperKeyTap = HyperKeyTap()
    let windowMover = WindowMover()
    let spaceSwitcher = SpaceSwitcher()
    let inputSourceSwitcher = InputSourceSwitcher()
    let settings: AppSettings
    /// Mirrors settings into settings.json; nil while the Backup pane's switch is off.
    @ObservationIgnored private var settingsFile: SettingsFileRepository?
    /// The file's launcher items, kept to apply a waiting record once its app is installed.
    @ObservationIgnored private var launcherSettingsFile: LauncherSettingsFile?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private let iconStyle = IconStyleMonitor()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let aliases = AliasStore()
    let fallbacks = FallbackStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let regionNumberFormat = RegionNumberFormatMonitor()
    let calendarStore = CalendarStore()
    let meetingClock = MeetingClock()
    let updateChecker = UpdateCheckStore()
    let supportReminders: SupportReminderStore
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let pinnedEmoji = PinnedEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteState()
    let fileSearch = FileSearchSession()
    let menuSearch = MenuSearchSession()
    let windowSwitch = WindowSwitchSession()
    let activationPolicy = ActivationPolicy()
    let uninstall = UninstallSession()
    let customCommandArguments = CustomCommandArgumentSession()
    let notesStore: NotesStore
    let extensions: ExtensionManager
    let plugins = PluginManager()
    let docks = DockStore()
    let chatHistory: ChatHistoryStore
    let aiChat: AIChatState
    let aiSettings = AISettingsStore(
        environmentStore: .keychain,
        isAppleIntelligenceAvailable: { AppleIntelligenceProvider.status().isAvailable })
    let mcpSettings = MCPSettingsStore()
    let assistants = AssistantStore()
    let skills: SkillStore
    let mcpOAuth = MCPOAuthManager()
    @ObservationIgnored private(set) lazy var mcp = MCPServerManager(oauth: mcpOAuth)
    let quickActionSettings = QuickActionSettingsStore()
    let customQuickActions = CustomQuickActionStore()
    let chatGPTSubscription = ChatGPTSubscriptionManager()
    let installedAI = InstalledAIManager()
    @ObservationIgnored private var appliedLaunchRevisions: [InstalledAIKind: Int] = [:]

    /// Set when a layout editor should open with Settings; the pane consumes it.
    var pendingWindowLayoutEdit: WindowLayoutEditRequest?

    @ObservationIgnored private(set) lazy var snippetCoordinator = SnippetCoordinator(
        store: snippetsStore, listener: snippetListener, injector: textInjector,
        clipboardStore: clipboardStore, appIndex: appIndex, settings: settings,
        windowController: windowController, paletteCoordinator: paletteCoordinator,
        showMessage: { [unowned self] in self.showMessage($0, tone: $1) }, core: self)
    @ObservationIgnored private(set) lazy var dictationCoordinator = DictationCoordinator(
        settings: settings, hotKeys: hotKeys, models: dictationModels, injector: textInjector,
        audioDucker: dictationAudioDucker,
        confirmEnable: { [unowned self] in
            await self.confirm(
                title: "Enable Dictation?",
                message: "Onecast needs microphone access for dictation and Accessibility to paste into "
                    + "other apps. Audio is processed on this Mac.",
                symbol: "waveform", confirmTitle: "Continue", tone: .neutral,
                confirmRole: .standard)
        },
        showMessage: { [unowned self] in self.showMessage($0, tone: $1) })
    @ObservationIgnored private(set) lazy var quicklinkCoordinator = QuicklinkCoordinator(
        store: quicklinks, settings: settings,
        appIndex: appIndex, injector: textInjector, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        windowController: windowController,
        paletteCoordinator: paletteCoordinator,
        clipboardHistory: { [unowned self] in self.snippetCoordinator.clipboardHistoryForExpansion() },
        core: self)

    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: appIndex,
        fileSearch: fileSearch, menuSearch: menuSearch, windowSwitch: windowSwitch,
        windowController: windowController)
    /// Its own window and lifecycle: neither coordinator shows or closes the other's surface.
    @ObservationIgnored private(set) lazy var settingsCoordinator = SettingsCoordinator(core: self)
    @ObservationIgnored private(set) lazy var onboardingCoordinator = OnboardingCoordinator(
        core: self)
    @ObservationIgnored private(set) lazy var systemActionCoordinator = SystemActionCoordinator(
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var uninstallCoordinator = UninstallCoordinator(
        session: uninstall, palette: palette, paletteCoordinator: paletteCoordinator,
        appIndex: appIndex, runningApps: runningApps, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases, core: self)
    @ObservationIgnored private(set) lazy var extensionCoordinator = ExtensionCoordinator(
        extensions: extensions, palette: palette, paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator, settings: settings, core: self)
    @ObservationIgnored private(set) lazy var pluginCoordinator = PluginCoordinator(
        plugins: plugins, palette: palette, paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator, settings: settings, core: self)
    @ObservationIgnored private(set) lazy var pluginWindowController = PluginWindowController(
        core: self)
    @ObservationIgnored private(set) lazy var dockCoordinator = DockCoordinator(
        store: docks, settings: settings, core: self)
    @ObservationIgnored private(set) lazy var dockSwitchCoordinator = DockSwitchCoordinator(
        store: docks, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
        favorites: favorites, visibility: visibility, ranking: launcherRanking, aliases: aliases,
        core: self)
    @ObservationIgnored private(set) lazy var windowCommandCoordinator = WindowCommandCoordinator(
        settings: settings, paletteCoordinator: paletteCoordinator, windowMover: windowMover,
        spaceSwitcher: spaceSwitcher, customSizes: customWindowSizes)
    @ObservationIgnored private(set) lazy var customWindowSizeCoordinator =
        CustomWindowSizeCoordinator(
            store: customWindowSizes, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
            favorites: favorites, visibility: visibility, ranking: launcherRanking,
            aliases: aliases, core: self)
    @ObservationIgnored private(set) lazy var windowShortcutPresetCoordinator =
        WindowShortcutPresetCoordinator(hotKeys: hotKeys, core: self)
    @ObservationIgnored private(set) lazy var windowLayoutCoordinator = WindowLayoutCoordinator(
        store: windowLayouts, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
        favorites: favorites, visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var customCommandCoordinator = CustomCommandCoordinator(
        store: customCommands, argumentSession: customCommandArguments, settings: settings,
        appIndex: appIndex,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        hotKeys: hotKeys, favorites: favorites, visibility: visibility,
        ranking: launcherRanking, aliases: aliases, activationPolicy: activationPolicy, core: self)
    @ObservationIgnored private(set) lazy var appleShortcutCoordinator = AppleShortcutCoordinator(
        settings: settings, appIndex: appIndex, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var notesCoordinator = NotesCoordinator(
        store: notesStore,
        settings: settings,
        appIndex: appIndex,
        core: self)

    @ObservationIgnored private(set) lazy var launcherCoordinator = LauncherCoordinator(
        ranking: launcherRanking, windowController: windowController,
        paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator,
        customCommandCoordinator: customCommandCoordinator,
        systemActionCoordinator: systemActionCoordinator,
        quicklinkCoordinator: quicklinkCoordinator,
        windowCommandCoordinator: windowCommandCoordinator,
        windowLayoutCoordinator: windowLayoutCoordinator,
        snippetCoordinator: snippetCoordinator, fileSearchCoordinator: fileSearchCoordinator,
        menuSearchCoordinator: menuSearchCoordinator,
        windowSwitchCoordinator: windowSwitchCoordinator,
        notesCoordinator: notesCoordinator, extensionCoordinator: extensionCoordinator,
        pluginCoordinator: pluginCoordinator,
        calendarCoordinator: calendarCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var fallbackCoordinator = FallbackCoordinator(
        store: fallbacks, quicklinks: quicklinks, settings: settings, core: self)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        clipboardStore: clipboardStore, clipboardManager: clipboardManager, settings: settings,
        appIndex: appIndex, palette: palette, windowController: windowController,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var emojiCoordinator = EmojiCoordinator(
        frequentEmoji: frequentEmoji, settings: settings, windowController: windowController,
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var calculatorCoordinator = CalculatorCoordinator(
        calcHistory: calcHistory, paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var calendarCoordinator = CalendarCoordinator(
        store: calendarStore, clock: meetingClock, appIndex: appIndex, settings: settings,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var fileSearchCoordinator = FileSearchCoordinator(
        settings: settings, appIndex: appIndex, session: fileSearch, palette: palette,
        paletteCoordinator: paletteCoordinator, windowController: windowController, core: self)
    @ObservationIgnored private(set) lazy var menuSearchCoordinator = MenuSearchCoordinator(
        settings: settings, appIndex: appIndex, session: menuSearch, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var windowSwitchCoordinator = WindowSwitchCoordinator(
        settings: settings, appIndex: appIndex, session: windowSwitch, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var cameraCoordinator = CameraCoordinator(core: self)
    @ObservationIgnored private(set) lazy var updateCoordinator = UpdateCoordinator(
        store: updateChecker, core: self)
    @ObservationIgnored private(set) lazy var supportCoordinator = SupportCoordinator(
        store: supportReminders, core: self)
    @ObservationIgnored private(set) lazy var quickActionCoordinator = QuickActionCoordinator(
        settings: settings, store: quickActionSettings, customActions: customQuickActions,
        injector: textInjector, appIndex: appIndex, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var schedulerCoordinator = SchedulerCoordinator(
        store: scheduledTasks, settings: settings, notifications: notificationPresenter,
        appIndex: appIndex)
    @ObservationIgnored private(set) lazy var schedulerEditorCoordinator =
        SchedulerEditorCoordinator(store: scheduledTasks, core: self)
    @ObservationIgnored private(set) lazy var presentationCoordinator = PresentationCoordinator(
        settings: settings, appIndex: appIndex, core: self)
    @ObservationIgnored private(set) lazy var computerUseBridge =
        AIToolBridge(ComputerUseTool.toolset(controller: computerController))
    @ObservationIgnored private(set) lazy var browserRelayBridge = AIToolBridge(
        BrowserRelayTool.toolset(port: { [aiSettings] in aiSettings.browserRelayPort }))
    @ObservationIgnored private(set) lazy var mcpCoordinator = MCPCoordinator(
        settings: settings, store: mcpSettings, manager: mcp, core: self)
    @ObservationIgnored private(set) lazy var aiChatCoordinator = AIChatCoordinator(
        chat: aiChat, history: chatHistory, scope: .dynamic, settings: settings, appIndex: appIndex,
        palette: palette, paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator, core: self)
    @ObservationIgnored private(set) lazy var aiChatWindowController = AIChatWindowController(
        core: self)

    @ObservationIgnored private lazy var windowController = PaletteWindowController(core: self)
    @ObservationIgnored private lazy var messageHUD = MessageHUDController(settings: settings)
    /// Every confirmation, report and prompt; it also stops a held hotkey stacking them.
    @ObservationIgnored private lazy var dialogs = DialogController(settings: settings)
    private let healthTicker = HealthTicker()
    @ObservationIgnored let notificationPresenter = NotificationPresenter(
        screen: { NSScreen.primary })

    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        let chatHistory = ChatHistoryStore(directory: AppPaths.applicationSupport())
        skills = SkillStore(
            directory: AppPaths.applicationSupport().appendingPathComponent("skills", isDirectory: true))
        self.launcherRanking = launcherRanking
        self.settings = settings
        self.chatHistory = chatHistory
        supportReminders = SupportReminderStore(settings: settings)
        aiChat = AIChatState(history: chatHistory)
        appIndex = AppIndex(ranking: launcherRanking, aliases: aliases)
        let clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
        extensions = ExtensionManager(clipboardStore: clipboardStore)
        snippetsStore = SnippetsStore(repository: Self.snippetsRepository(for: settings))
        textInjector = TextInjector(
            clipboardManager: clipboardManager,
            settings: settings)
        let noteSelectionKey = "notesActiveFileName"
        notesStore = NotesStore(
            repository: Self.notesRepository(for: settings),
            loadSelection: {
                UserDefaults.standard.string(forKey: noteSelectionKey).map(NoteID.init(rawValue:))
            },
            saveSelection: { UserDefaults.standard.set($0?.rawValue, forKey: noteSelectionKey) })
    }

    func start() {
        Signposts.interval("AppCore.start") {
            // Shorten AppKit's ~2–3s tooltip delay; registration domain, so a user default wins.
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            dictationAudioDucker.recover()
            applyAppearance()
            observeEffectiveAppearance()
            pinnedEmoji.onPersistenceFailure = { [weak self] in
                self?.showMessage("Couldn't save Emoji & Symbols pins", tone: .danger)
            }

            appIndex.start(settings: settings)
            clipboardCoordinator.applyEnabled()
            extensions.start(appIndex: appIndex, coordinator: extensionCoordinator)
            extensionCoordinator.applyEnabled()
            plugins.start(appIndex: appIndex)
            pluginCoordinator.applyEnabled()
            dockCoordinator.start()
            dockCoordinator.applyEnabled()
            fileSearchCoordinator.applyEnabled()
            windowSwitchCoordinator.applyEnabled()
            menuSearchCoordinator.applyEnabled()
            fileSearchCoordinator.applyPolicy()
            notesCoordinator.applyEnabled()
            installedAI.launchSettings = { [aiSettings] in aiSettings.launch(for: $0) }
            chatGPTSubscription.launchSettings = { [aiSettings] in aiSettings.launch(for: .codex) }
            aiChatCoordinator.applyEnabled()
            mcpCoordinator.applyEnabled()
            assistants.onChange = { [weak self] _ in
                self?.aiChatCoordinator.applyAssistantsPresence()
            }
            customQuickActions.onChange = { [weak self] _ in
                self?.quickActionCoordinator.applyCustomQuickActionsPresence()
            }
            // Before `hotKeys.start` even when off: the prune reads it.
            customQuickActions.load()
            quickActionCoordinator.applyEnabled()
            customCommands.onChange = { [weak self] _ in
                self?.customCommandCoordinator.applyCustomCommandsPresence()
            }
            customCommandCoordinator.applyCustomCommandsPresence()
            applyWindowCommandsPresence()
            customWindowSizes.onChange = { [weak self] _ in
                self?.customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            }
            customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            windowLayouts.onChange = { [weak self] _ in
                self?.windowLayoutCoordinator.applyWindowLayoutsPresence()
            }
            windowLayoutCoordinator.applyWindowLayoutsPresence()
            quicklinks.onChange = { [weak self] _ in
                self?.quicklinkCoordinator.applyQuicklinksPresence()
            }
            // Before `hotKeys.start` even when off: the prune reads it. docs/features/quicklinks.md
            quicklinks.load()
            quicklinkCoordinator.applyQuicklinksPresence()
            appleShortcutCoordinator.applyPresence()
            paletteCoordinator.onLauncherShown = { [weak self] in
                self?.appleShortcutCoordinator.refresh()
            }
            paletteCoordinator.onScreenOpening = { [weak self] mode in
                switch mode {
                case .menuSearch: self?.menuSearchCoordinator.load()
                case .switchWindows: self?.windowSwitchCoordinator.load()
                default: break
                }
            }
            updateCoordinator.applyEnabled()
            calendarCoordinator.applyEnabled()
            Task { await appIndex.refresh() }
            Task { await emojiIndex.load(languages: Locale.preferredLanguages) }
            currencyRates.start()
            updateChecker.onUpdateAvailable = { [weak self] release in
                self?.updateCoordinator.presentIfAvailable(release) ?? true
            }
            updateCoordinator.applyAutomaticChecking()
            supportReminders.onDue = { [weak self] in self?.supportCoordinator.presentIfDue() }
            supportReminders.start()

            hyperKeyTap.healthTicker = healthTicker
            hotKeys.modifierTapMonitor.healthTicker = healthTicker
            snippetListener.healthTicker = healthTicker

            hotKeys.onTogglePalette = { [weak self] in self?.paletteCoordinator.togglePalette() }
            hotKeys.onToggleAIBar = { [weak self] in self?.aiChatCoordinator.toggleBar() }
            hotKeys.dictationEnabled = settings.dictationEnabled
            hotKeys.dictationHoldToTalk = settings.dictationMode == .pushToTalk
            hotKeys.onDictationPressed = { [weak self] in self?.dictationCoordinator.pressed() }
            hotKeys.onDictationReleased = { [weak self] in self?.dictationCoordinator.released() }
            hotKeys.onDictationCancelled = { [weak self] in self?.dictationCoordinator.cancel() }
            hotKeys.onRunCommand = { [weak self] id in self?.launcherCoordinator.runCommand(id) }
            hotKeys.onRunCustomCommand = { [weak self] id in
                self?.customCommandCoordinator.runCustomCommand(id: id)
            }
            hotKeys.onOpenAssistant = { [weak self] id in self?.aiChatCoordinator.openAssistant(id: id) }
            hotKeys.onRunSystemAction = { [weak self] id in
                self?.systemActionCoordinator.runSystemAction(id: id)
            }
            hotKeys.onRunWindowCommand = { [weak self] id in
                self?.windowCommandCoordinator.runWindowCommand(id: id)
            }
            hotKeys.onRunWindowLayout = { [weak self] id in
                self?.windowLayoutCoordinator.runWindowLayout(id: id)
            }
            hotKeys.onRunCustomWindowSize = { [weak self] id in
                self?.windowCommandCoordinator.runCustomWindowSize(id: id)
            }
            hotKeys.onOpenQuicklink = { [weak self] id in
                self?.quicklinkCoordinator.openQuicklink(id: id)
            }
            hotKeys.onRunQuickAction = { [weak self] id in
                self?.quickActionCoordinator.run(id: id)
            }
            hotKeys.onRunAppleShortcut = { [weak self] id in
                self?.appleShortcutCoordinator.run(id: id)
            }
            hotKeys.onExpandSnippet = { [weak self] id in
                self?.snippetCoordinator.expandSnippetFromHotKey(id: id)
            }
            hotKeys.onRunExtensionCommand = { [weak self] entryID in
                self?.extensionCoordinator.runExtensionCommand(entryID: entryID)
            }
            hotKeys.onRunPluginCommand = { [weak self] entryID in
                self?.pluginCoordinator.runPluginCommand(entryID: entryID)
            }
            hotKeys.onRunScheduledTask = { [weak self] id in
                self?.schedulerCoordinator.runTask(id: id)
            }
            hotKeys.onRunDockSetup = { [weak self] id in
                self?.dockSwitchCoordinator.switchToSetup(id: id)
            }
            hotKeys.onToggleDockVisibility = { [weak self] id in
                self?.dockSwitchCoordinator.toggleDock(id: id)
            }
            extensions.onDidUninstall = { [weak self] entryIDs in
                self?.extensionCoordinator.removeExtensionReferences(entryIDs: entryIDs)
            }
            appIndex.onScan = { [weak self] in
                guard let self else { return }
                hotKeys.removeAppBindings(where: appIndex.isUninstalled)
                // After the first scan, so the file's apps and panes have entries to match.
                if settings.settingsFileEnabled, settingsFile == nil {
                    startSettingsFile(importing: true)
                } else if let launcherSettingsFile {
                    reportSettingsFileIssues(launcherSettingsFile.applyInstalled())
                }
            }
            plugins.onDidUninstall = { [weak self] entryIDs in
                self?.pluginCoordinator.removePluginReferences(entryIDs: entryIDs)
            }
            hotKeys.displayName = { [weak self] action in self?.hotKeyDisplayName(for: action) }
            hotKeys.allowsAction = { [weak self] action in
                guard let self, visibility.allowsHotKey(action) else { return false }
                if action == .dictation { return settings.dictationEnabled }
                // A disabled feature drops its commands from the launcher; their shortcuts go too.
                guard case .command(let id) = action else { return true }
                return appIndex.isCommandEnabled(id)
            }
            KeyShortcut.displayedHyperChord = { [settings] in
                guard settings.hyperKey != .none else { return nil }
                return KeyShortcut.hyperChord(includesShift: settings.hyperKeyIncludesShift)
            }
            SystemActionRunner.onAsyncFailure = { [weak self] id, failure in
                self?.systemActionCoordinator.presentSystemActionFailure(id: id, failure: failure)
            }
            schedulerCoordinator.applyEnabled()
            presentationCoordinator.applyEnabled()
            hotKeys.start(
                customCommandIDs: Set(customCommands.commands.map(\.id)),
                quicklinkIDs: Set(quicklinks.quicklinks.map(\.id)),
                windowLayoutIDs: Set(windowLayouts.layouts.map(\.id)),
                customWindowSizeIDs: Set(customWindowSizes.sizes.map(\.id)),
                quickActionIDs: Set(customQuickActions.actions.map(\.id)),
                assistantIDs: Set(assistants.assistants.map(\.id)),
                scheduledTaskIDs: Set(scheduledTasks.tasks.map(\.id)),
                dockSetupIDs: Set(docks.configuration.setups.map(\.id)),
                dockIDs: Set(docks.docks.map(\.id)))
            // Keeps running while Carbon pauses: the recorder needs its rewritten flags.
            hyperKeyTap.start(settings: settings)

            snippetsStore.onSnapshot = { [weak self] snapshot in
                guard let self else { return }
                self.snippetCoordinator.applySnippetsLauncherPresence()
                self.snippetListener.update(snapshot.records)
                self.hotKeys.removeSnippetBindings(keeping: snapshot.fileIDs)
            }
            // Off out of the box, so an unused feature costs no load, watcher or tap.
            if settings.snippetsEnabled {
                Task { await snippetsStore.start() }
                snippetCoordinator.startSnippetKeywordListener()
            }
            // Unconditional: a disabled feature has to take its command rows down with it.
            snippetCoordinator.applySnippetsLauncherPresence()

            observeFeatureSwitches()

            // First launch binds no hotkey, so guide once; the marker is written at show-time.
            if !OnboardingState.hasOnboarded {
                OnboardingState.markShown()
                onboardingCoordinator.showOnboarding()
            }
        }
    }

    /// Clicking the Dock icon: raise whichever window is already open, else summon the launcher.
    func handleReopen() {
        if settingsCoordinator.focusExisting() { return }
        if onboardingCoordinator.focusExisting() { return }
        if updateCoordinator.focusExisting() { return }
        if supportCoordinator.focusExisting() { return }
        if customCommandCoordinator.focusOutputWindow() { return }
        paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
    }

    func handleOpenURL(_ url: URL) {
        switch ExtensionOAuthSession.handleCallbackURL(url) {
        case .delivered:
            paletteCoordinator.showPalette(mode: .extensionCommand, restoreAnyMode: true)
            return
        case .expired:
            showMessage("Sign-in expired — run the command again", tone: .danger)
            return
        case .ignored:
            break
        }
        if DockURL.claims(url) {
            dockSwitchCoordinator.handle(url)
            return
        }
        guard ExtensionDeepLink.claims(url) else { return }
        guard let link = ExtensionDeepLink.parse(url: url) else {
            paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
            return
        }
        extensionCoordinator.runDeepLink(link)
    }

    /// The store-backed half of the conflict message; `HotKeyManager` names the catalogs itself.
    private func hotKeyDisplayName(for action: HotKeyAction) -> String? {
        switch action {
        case .app(let bundleID):
            return appIndex.apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
        case .settingsPane(let bundleID):
            return appIndex.apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?
                .name
        case .customCommand(let id):
            return customCommands.command(id: id)?.name
        case .quicklink(let id):
            return quicklinks.quicklink(id: id)?.name
        case .quickAction(let id):
            return customQuickActions.action(id: id)?.name
        case .assistant(let id):
            return assistants.assistant(id: id)?.name
        case .windowLayout(let id):
            return windowLayouts.layout(id: id)?.name
        case .customWindowSize(let id):
            return customWindowSizes.size(id: id)?.name
        case .appleShortcut(let id):
            return appleShortcutCoordinator.name(of: id)
        case .snippet(let id):
            return snippetsStore.record(id: id)?.snippet.name
        case .extensionCommand(let entryID):
            return appIndex.apps.first { $0.kind == .extensionCommand && $0.id == entryID }?.name
        case .pluginCommand(let entryID):
            return appIndex.apps.first { $0.kind == .plugin && $0.id == entryID }?.name
        case .scheduledTask(let id):
            return scheduledTasks.task(id: id)?.name
        case .dockSetup(let id):
            return docks.setup(id: id).map { "Switch to " + $0.name }
        case .dockVisibility(let id):
            return docks.dock(id: id).map { "Show/Hide " + $0.name }
        case .togglePalette, .toggleAIBar, .dictation, .command, .systemAction, .windowCommand:
            return nil
        }
    }

    func flushNotesForTermination() async {
        await notesCoordinator.prepareForTermination()
    }

    func stopDictationForTermination() async {
        if settings.dictationEnabled { dictationCoordinator.prepareForTermination() }
        dictationAudioDucker.restoreImmediately()
        await dictationAudioDucker.waitForTransition()
        await dictationModels.stop()
    }

    /// Idempotent: both switches are tracked, and either one flipping re-runs the whole decision.
    func applyClipboardTextSearch() {
        guard settings.clipboardEnabled, settings.clipboardTextSearchEnabled else {
            clipboardStore.onItemsChanged = nil
            clipboardStore.onSearchResultsChanged = nil
            clipboardStore.setTextSearchEnabled(false)
            clipboardTextIndexer?.stop()
            return
        }
        guard clipboardStore.setTextSearchEnabled(true) else {
            showMessage("Couldn't enable text recognition for clipboard history.", tone: .danger)
            return
        }
        clipboardStore.setTextSearchActive(palette.isVisible)
        // Kept across a disable: the indexer reschedules itself once a cancelled run winds down.
        let indexer =
            clipboardTextIndexer
            ?? ClipboardTextIndexer(store: clipboardStore, canRun: { ClipboardTextIndexer.isSystemIdle })
        clipboardTextIndexer = indexer
        clipboardStore.onItemsChanged = { [weak indexer] in indexer?.schedule() }
        clipboardStore.onSearchResultsChanged = { [weak self] query, previous, current in
            self?.clipboardCoordinator.followSearchResults(query: query, previous: previous, current: current)
        }
        indexer.start()
    }

    func prepareForTermination() {
        if settings.dictationEnabled { dictationCoordinator.prepareForTermination() }
        settingsFile?.flush()
        clipboardTextIndexer?.stop()
        // Caps Lock first: its remap is the one teardown that outlives the process.
        hyperKeyTap.prepareForTermination()
        windowLayoutCoordinator.prepareForTermination()
        dockCoordinator.prepareForTermination()
        presentationCoordinator.prepareForTermination()
        inputSourceSwitcher.endSession()
        textInjector.prepareForTermination()
        snippetListener.stop()
        snippetsStore.stop()
        aiChat.cancel()
        aiChatWindowController.closeAllForQuit()
        chatGPTSubscription.stop()
        mcpOAuth.stop()
        mcp.stop()
        installedAI.stop()
    }

    /// Only the tool whose own path or variables changed is checked again; the rest keep running.
    private func applyInstalledLaunches() {
        let revisions = aiSettings.launchRevisions
        let enabled =
            settings.aiEnabled || settings.quickActionsEnabled
            ? aiSettings.enabledInstalledProviders : []
        for kind in InstalledAIKind.allCases where appliedLaunchRevisions[kind] != revisions[kind] {
            guard enabled.contains(kind) else { continue }
            if kind == .codex {
                chatGPTSubscription.stop()
                chatGPTSubscription.refresh()
            } else {
                installedAI.refresh(kind: kind)
            }
        }
        appliedLaunchRevisions = revisions
    }

    @discardableResult
    func applyInstalledAILifecycle() -> Task<Void, Never> {
        let enabledKinds =
            settings.aiEnabled || settings.quickActionsEnabled
            ? aiSettings.enabledInstalledProviders : []
        var tasks: [Task<Void, Never>] = []
        if enabledKinds.contains(.codex) {
            tasks.append(
                chatGPTSubscription.phase == .idle
                    ? chatGPTSubscription.refresh()
                    : chatGPTSubscription.currentRefreshTask())
        } else {
            chatGPTSubscription.stop()
        }
        tasks.append(installedAI.ensure(enabledKinds: enabledKinds))
        return Task { for task in tasks { await task.value } }
    }

    func aiProvider(cliTools: AICLIToolConfig? = nil) throws -> any AIProvider {
        try AIProviderFactory.make(
            settings: aiSettings, subscription: chatGPTSubscription, installedAI: installedAI,
            cliTools: cliTools)
    }

    /// Chat's route for a specific selection — an Assistant's chosen model, distinct from the default.
    func aiProvider(for selection: AIModelSelection, cliTools: AICLIToolConfig? = nil) throws
        -> any AIProvider
    {
        try AIProviderFactory.make(
            selection: selection, settings: aiSettings, subscription: chatGPTSubscription,
            installedAI: installedAI, cliTools: cliTools)
    }

    /// Permissive guardrails: the text transformed is the reader's own, which `.default` refuses.
    func quickActionProvider(for action: QuickAction) throws -> any AIProvider {
        quickActionSettings.repairModel(
            against: aiSettings.connections, fallback: aiSettings.defaultModel)
        guard let selection = quickActionSettings.model(for: action) ?? aiSettings.defaultModel
        else {
            throw AIProviderError.unavailable("Choose a model in Settings \u{2192} Quick Actions.")
        }
        return try AIProviderFactory.make(
            selection: selection, settings: aiSettings, subscription: chatGPTSubscription,
            installedAI: installedAI,
            guardrails: .permissiveContentTransformations)
    }

    // MARK: - Feature switches

    private func observeFeatureSwitches() {
        track(
            { _ = $0.automaticallyCheckForUpdates },
            reproject: { $0.updateCoordinator.applyAutomaticChecking() })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowManagementShowInLauncher
            },
            reproject: {
                $0.applyWindowCommandsPresence()
                $0.customWindowSizeCoordinator.applyCustomWindowSizesPresence()
            })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowLayoutsShowInLauncher
            }, reproject: { $0.windowLayoutCoordinator.applyWindowLayoutsPresence() })
        track(
            {
                _ = $0.customCommandsEnabled
                _ = $0.customCommandsShowInLauncher
            }, reproject: { $0.customCommandCoordinator.applyCustomCommandsPresence() })
        track(
            {
                _ = $0.quicklinksEnabled
                _ = $0.quicklinksShowInLauncher
            }, reproject: { $0.quicklinkCoordinator.applyQuicklinksPresence() })
        track(
            { _ = $0.appleShortcutsEnabled },
            reproject: { $0.appleShortcutCoordinator.applyPresence() })
        track(
            { _ = $0.clipboardEnabled }, reproject: { $0.clipboardCoordinator.applyEnabled() })
        track(
            { _ = $0.clipboardTextSearchEnabled }, reproject: { $0.applyClipboardTextSearch() })
        track({ _ = $0.fileSearchEnabled }, reproject: { $0.fileSearchCoordinator.applyEnabled() })
        // Two features, one switch: each coordinator gates only its own command and mode.
        track(
            { _ = $0.navigationEnabled },
            reproject: {
                $0.windowSwitchCoordinator.applyEnabled()
                $0.menuSearchCoordinator.applyEnabled()
            })
        track({ _ = $0.notesEnabled }, reproject: { $0.notesCoordinator.applyEnabled() })
        track(
            { _ = $0.aiEnabled },
            reproject: {
                $0.aiChatCoordinator.applyEnabled()
                _ = $0.applyInstalledAILifecycle()
            })
        track(
            { _ = $0.aiAssistantsShowInLauncher },
            reproject: { $0.aiChatCoordinator.applyAssistantsPresence() })
        track(
            { _ = $0.dictationIdleRelease },
            reproject: {
                $0.dictationModels.setIdleRelease($0.settings.dictationIdleRelease)
            })
        track(
            {
                _ = $0.dictationEnabled
                _ = $0.dictationMode
            },
            reproject: {
                $0.hotKeys.dictationHoldToTalk = $0.settings.dictationMode == .pushToTalk
                $0.hotKeys.dictationEnabled = $0.settings.dictationEnabled
            })
        track(
            {
                _ = $0.aiEnabled
                _ = $0.mcpEnabled
            }, reproject: { $0.mcpCoordinator.applyEnabled() })
        track(
            { _ = $0.quickActionsEnabled },
            reproject: { $0.quickActionCoordinator.applyEnabled() })
        track(
            {
                _ = $0.calendarEnabled
                _ = $0.calendarShowInLauncher
                _ = $0.calendarLauncherLimit
            }, reproject: { $0.calendarCoordinator.applyEnabled() })
        track(
            { _ = $0.calendarSpan },
            reproject: { $0.calendarCoordinator.applySpan() })
        track(
            {
                _ = $0.autoJoinMeetings
                _ = $0.menuBarEvents
                _ = $0.calendarMenuBarDisplay
                _ = $0.menuBarLinkedEventsOnly
                _ = $0.hideCurrentEvent
            }, reproject: { $0.calendarCoordinator.applyClock() })
        track(
            {
                _ = $0.fileSearchScopes
                _ = $0.fileSearchIgnorePatterns
            }, reproject: { $0.fileSearchCoordinator.applyPolicy() })
        track({ _ = $0.snippetsEnabled }, reproject: { $0.snippetCoordinator.applySnippetsEnabled() })
        // Not a feature switch, but the same re-projection: a combo has the chord's ⇧ bit baked in.
        track({ _ = $0.hyperKeyIncludesShift }, reproject: { $0.applyHyperChord() })
        track(
            { _ = $0.snippetsShowInLauncher },
            reproject: { $0.snippetCoordinator.applySnippetsLauncherPresence() })
        track(
            {
                _ = $0.schedulerEnabled
                _ = $0.schedulerShowInLauncher
            }, reproject: { $0.schedulerCoordinator.applySchedulerEnabled() })
        track(
            {
                _ = $0.presentationEnabled
                _ = $0.presentationShowInLauncher
            }, reproject: { $0.presentationCoordinator.applyEnabled() })
        track(
            {
                _ = $0.presentationWindowSize
                _ = $0.presentationMarginPercent
            }, reproject: { $0.presentationCoordinator.refit() })
        track({ _ = $0.appearance }, reproject: { $0.applyAppearance() })
        track({ _ = $0.interfaceSize }, reproject: { $0.windowController.applyInterfaceSize() })
        // Settings panes did these on change; settings.json can change them with no pane open.
        track(
            { _ = $0.clipboardRetention },
            reproject: { $0.clipboardCoordinator.applyRetention($0.settings.clipboardRetention) })
        track(aiSettings, { _ = $0.retention }, reproject: { $0.aiChatCoordinator.applyRetention() })
        track(aiSettings, { _ = $0.launchRevisions }, reproject: { $0.applyInstalledLaunches() })
        track(
            { _ = $0.extensionsShowInLauncher },
            reproject: { $0.extensionCoordinator.applyExtensionsLauncherPresence() })
        track({ _ = $0.snippetsFolder }, reproject: { $0.applySnippetsFolder() })
        track({ _ = $0.notesFolder }, reproject: { $0.applyNotesFolder() })
        track(
            { _ = $0.pluginsShowInLauncher },
            reproject: { $0.pluginCoordinator.applyPluginsLauncherPresence() })
        track(
            {
                _ = $0.docksEnabled
                _ = $0.dockWidgetsEnabled
            }, reproject: { $0.dockCoordinator.applyEnabled() })
    }

    /// `.system` resolves to `nil`, so AppKit follows macOS with nothing polling.
    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    /// IconCache is told here, not from `applyAppearance()`, which never fires under `.system`.
    private func observeEffectiveAppearance() {
        // Synchronous on main, so no row can cache a tile under the outgoing appearance's key.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial]) { app, _ in
            MainActor.assumeIsolated { IconCache.setDarkSurface(app.effectiveAppearance.isDark) }
        }
    }

    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        track(settings, reads, reproject: reproject)
    }

    /// Fires synchronously on main before the write lands, so the task re-arms and re-reads.
    private func track<Store: AnyObject & Sendable>(
        _ store: Store,
        _ reads: @escaping @Sendable @MainActor (Store) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(store)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(store, reads, reproject: reproject)
                reproject(self)
            }
        }
    }

    /// Without a Hyper key the chord means nothing, so a literal ⌃⌥⌘ combo is left as recorded.
    private func applyHyperChord() {
        guard settings.hyperKey != .none else { return }
        hotKeys.retargetHyperBindings(includesShift: settings.hyperKeyIncludesShift)
    }

    private func applySnippetsFolder() {
        let repository = Self.snippetsRepository(for: settings)
        Task { await snippetsStore.relocate(to: repository) }
    }

    private func applyNotesFolder() {
        let repository = Self.notesRepository(for: settings)
        Task { await notesStore.relocate(to: repository) }
    }

    private static func snippetsRepository(for settings: AppSettings) -> SnippetRepository {
        SnippetRepository(
            snippetsDirectory: AppPaths.contentFolder(settings.snippetsFolder, named: "Snippets"))
    }

    private static func notesRepository(for settings: AppSettings) -> NotesRepository {
        NotesRepository(notesDirectory: AppPaths.contentFolder(settings.notesFolder, named: "Notes"))
    }

    private func applyWindowCommandsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setWindowCommandsVisible(visible)
    }

    // MARK: - Settings file

    /// Mirrors settings into settings.json from now on; `importing` applies the file's own first.
    func startSettingsFile(importing: Bool) {
        guard settingsFile == nil else { return }
        let shortcuts = HotKeySettingsFile(hotKeys: hotKeys)
        let launcher = LauncherSettingsFile(
            appIndex: appIndex, aliases: aliases, visibility: visibility, shortcuts: shortcuts)
        let file = SettingsFileRepository(
            fileURL: AppPaths.settingsFile(),
            bindings: SettingsFileSchema.bindings(
                settings: settings, ai: aiSettings, quickActions: quickActionSettings,
                shortcuts: shortcuts, launcher: launcher,
                windowManagement: WindowManagementSettingsFile(
                    sizes: customWindowSizes, layouts: windowLayouts, aliases: aliases,
                    shortcuts: shortcuts)),
            commit: shortcuts.commit)
        file.onIssues = { [weak self] issues in self?.reportSettingsFileIssues(issues) }
        settingsFile = file
        launcherSettingsFile = launcher
        settings.settingsFileEnabled = true
        file.start(importing: importing)
    }

    /// Stops the mirror; the file stays on disk as last written.
    func stopSettingsFile() {
        settingsFile?.flush()
        settingsFile = nil
        launcherSettingsFile = nil
        settings.settingsFileEnabled = false
    }

    private func reportSettingsFileIssues(_ issues: [SettingsFileIssue]) {
        guard let summary = SettingsFileIssue.summary(issues) else { return }
        showMessage(summary, tone: .danger)
    }

    // MARK: - Interruption

    /// What the app is in the middle of; the update prompt and the support reminder both ask first.
    var currentActivity: UpdateActivity {
        UpdateActivity(
            isExpandingSnippet: textInjector.isDelivering,
            isRunningExtension: extensions.running != nil,
            isUninstalling: uninstall.isTrashing,
            isRecordingHotKey: hotKeys.recordingAction != nil,
            isPromptingForArguments: customCommandArguments.isActive,
            isShowingDialog: isShowingDialog,
            isPaletteVisible: paletteCoordinator.isVisible)
    }

    /// Whether a window may take focus without interrupting something the user started.
    var canInterruptUser: Bool { UpdateReadiness.evaluate(currentActivity) == nil }

    // MARK: - Dialogs, routed here so `dialogs` stays the single owner

    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {
        await dialogs.notice(title: title, message: message, symbol: symbol, tone: tone)
    }

    /// True while a dialog is up, so a surface behind one can tell it apart from losing focus.
    var isShowingDialog: Bool { dialogs.isPresenting }

    /// `tone` styles the glyph, `confirmRole` the button; separate on purpose.
    func confirm(
        title: String, message: String?, symbol: String?, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive,
        dismissTitle: String = "Cancel"
    ) async -> Bool {
        await dialogs.confirm(
            title: title, message: message, symbol: symbol, tone: tone, confirmTitle: confirmTitle,
            confirmRole: confirmRole, dismissTitle: dismissTitle)
    }

    /// A question with more than two answers; the returned index is into `options`.
    func choose(
        title: String, message: String?, symbol: String?, options: [DialogAction],
        defaultIndex: Int, tone: DialogTone = .neutral
    ) async -> Int {
        await dialogs.choose(
            title: title, message: message, symbol: symbol, tone: tone, options: options,
            defaultIndex: defaultIndex)
    }

    /// A failure with one usable second option; `true` when the user takes it.
    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async
        -> Bool
    {
        await dialogs.reportFailure(
            title: title, message: message, symbol: symbol, recovery: recovery)
    }

    /// The transient success/info pill, so `messageHUD` stays single-owned alongside `dialogs`.
    func showMessage(_ message: String, tone: DialogTone = .success) {
        messageHUD.show(message: message, tone: tone)
    }

    /// The same pill with a spinner, for work the reader started and cannot otherwise see running.
    func showProgress(_ message: String, onCancel: (() -> Void)? = nil) {
        messageHUD.showProgress(message: message, onCancel: onCancel)
    }

    func hideProgress() {
        messageHUD.dismiss()
    }

    /// The volume slider, so `dialogs` stays the single owner of every prompt in the app.
    func pickVolume(current: Float32) async -> Float32? {
        await dialogs.pickVolume(current: current)
    }

    /// The new-event prompt, for the same reason.
    func createEvent() async -> EventDraft? {
        await dialogs.createEvent()
    }

    /// The snippet argument prompt, for the same reason.
    func fillSnippetArguments(
        snippetName: String, arguments: [SnippetTemplateEngine.MissingArgument]
    ) async -> [String: String]? {
        await dialogs.fillSnippetArguments(snippetName: snippetName, arguments: arguments)
    }
}
