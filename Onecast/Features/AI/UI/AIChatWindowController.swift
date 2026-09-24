import AppKit
import Observation
import SwiftUI

/// One AI Chat window's live state: its chat, its scope's history, and replies it left running.
@MainActor
@Observable
final class AIChatWindowSession {
    let key: String
    let scope: UUID?
    let chat: AIChatState
    let history: ChatHistoryStore
    let coordinator: AIChatCoordinator
    let aiSettings: AISettingsStore
    let find = ChatFindState()
    /// Conversations switched away from mid-reply; each saves itself when its reply ends.
    private(set) var answering: [UUID: AIChatState] = [:]

    init(
        key: String, scope: UUID?, chat: AIChatState, history: ChatHistoryStore,
        coordinator: AIChatCoordinator, aiSettings: AISettingsStore
    ) {
        self.key = key
        self.scope = scope
        self.chat = chat
        self.history = history
        self.coordinator = coordinator
        self.aiSettings = aiSettings
    }

    /// Conversations with a reply still arriving, for the sidebar's spinners.
    var answeringIDs: Set<UUID> {
        var ids = Set(answering.values.filter(\.isStreaming).map(\.session.id))
        if chat.isStreaming { ids.insert(chat.session.id) }
        return ids
    }

    /// Leaving a chat never cancels its reply: it is parked, and reopening it picks it back up.
    func open(id: UUID) {
        guard chat.session.id != id else { return }
        parkIfAnswering()
        if let parked = answering.removeValue(forKey: id) {
            parked.handOff(to: chat)
        } else {
            chat.open(id: id)
        }
    }

    func newChat() {
        guard !chat.session.messages.isEmpty || chat.isStreaming else { return }
        parkIfAnswering()
        chat.startNewChat(userInitiated: true)
    }

    /// Takes over the launcher's conversation, a reply still arriving included.
    func adopt(_ source: AIChatState) {
        parkIfAnswering()
        coordinator.pin(to: scope, takingOver: source)
    }

    /// A parked reply would save the chat again once it ends, so it stops first.
    func delete(id: UUID) {
        answering.removeValue(forKey: id)?.cancel()
        coordinator.deleteChat(id: id)
    }

    private func parkIfAnswering() {
        answering = answering.filter { $0.value.isStreaming }
        guard chat.isStreaming else { return }
        let parked = AIChatState(history: history)
        parked.onReplyFinished = chat.onReplyFinished
        chat.handOff(to: parked)
        answering[parked.session.id] = parked
    }

    /// The window's ⌘G, its Return in the Find field, and the counter's chevrons all step here.
    func stepFind(_ delta: Int) {
        find.step(delta, in: chat.session.messages)
    }
}

/// One AI Chat window per scope, each with a sidebar of that scope's chats, reopened at launch.
@MainActor
final class AIChatWindowController {
    private unowned let core: AppCore
    private var windows: [String: Entry] = [:]

    private final class Entry {
        let session: AIChatWindowSession
        let window: AppWindowController

        init(session: AIChatWindowSession, window: AppWindowController) {
            self.session = session
            self.window = window
        }
    }

    /// Plain defaults, never a settings backup: which windows were open is machine-local.
    private static let persistenceKey = "aiChat.windows"
    private var didRestore = false

    private struct PersistedWindow: Codable {
        /// The scope key: "default" for the bar, else the Assistant's UUID string.
        var scope: String
        var allSpaces: Bool
        var keepInFront: Bool
    }

    init(core: AppCore) {
        self.core = core
    }

    /// Detach `source`'s conversation into `scope`'s window, opening it if it is not up yet.
    func popOut(scope: UUID?, from source: AIChatState) {
        let key = Self.key(for: scope)
        let entry = windows[key] ?? makeEntry(scope: scope, key: key)
        entry.session.adopt(source)
        show(entry, activating: true)
    }

    /// The window for `scope`, showing its most recent conversation when it opens.
    func showWindow(scope: UUID?) {
        let key = Self.key(for: scope)
        if let entry = windows[key] {
            show(entry, activating: true)
            return
        }
        let entry = makeEntry(scope: scope, key: key)
        entry.session.coordinator.restore(to: scope)
        show(entry, activating: true)
    }

    /// Opens a saved conversation in its scope's window, from the launcher's Chat History.
    func openInWindow(id: UUID, scope: UUID?) {
        let key = Self.key(for: scope)
        let entry = windows[key] ?? makeEntry(scope: scope, key: key)
        if windows[key] == nil { entry.session.coordinator.restore(to: scope) }
        entry.session.open(id: id)
        show(entry, activating: true)
    }

    func close(key: String) {
        windows[key]?.window.close()
    }

    func closeAll() {
        for key in Array(windows.keys) { close(key: key) }
    }

    /// Quitting closes the windows but remembers them, so they reopen on the next launch.
    func closeAllForQuit() {
        isQuitting = true
        closeAll()
    }

    private var isQuitting = false

    /// Reopens last launch's windows, minus any whose Assistant is gone, without stealing focus.
    func restoreIfNeeded() {
        guard !didRestore else { return }
        didRestore = true
        for saved in loadPersisted() {
            let scope: UUID?
            if saved.scope == "default" {
                scope = nil
            } else if let id = UUID(uuidString: saved.scope),
                core.assistants.assistant(id: id) != nil {
                scope = id
            } else {
                continue
            }
            let entry = makeEntry(scope: scope, key: saved.scope)
            entry.session.coordinator.restore(to: scope)
            show(entry, activating: false)
            if saved.allSpaces { setShowsOnAllSpaces(true, key: saved.scope) }
            if saved.keepInFront { setKeepsInFront(true, key: saved.scope) }
        }
        persist()
    }

    func showsOnAllSpaces(key: String) -> Bool {
        windows[key]?.window.window?.collectionBehavior.contains(.canJoinAllSpaces) ?? false
    }

    func keepsInFront(key: String) -> Bool {
        windows[key]?.window.window?.level == .floating
    }

    func setShowsOnAllSpaces(_ on: Bool, key: String) {
        guard let window = windows[key]?.window.window else { return }
        if on {
            window.collectionBehavior.remove(.moveToActiveSpace)
            window.collectionBehavior.insert(.canJoinAllSpaces)
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
        persist()
    }

    func setKeepsInFront(_ on: Bool, key: String) {
        windows[key]?.window.window?.level = on ? .floating : .normal
        persist()
    }

    // MARK: - Private

    private func show(_ entry: AIChatWindowSession, activating: Bool) {
        guard let window = windows[entry.key]?.window else { return }
        let session = entry
        let core = core
        window.show(
            chrome: AIChatWindowChrome(session: session, controller: self), activating: activating
        ) {
            AIChatSplitViewController(
                sidebar: AIChatSidebarView(session: session).windowEnvironment(core),
                detail: AIChatDetailView(session: session).windowEnvironment(core))
        }
        persist()
    }

    private func show(_ entry: Entry, activating: Bool) {
        windows[entry.session.key] = entry
        show(entry.session, activating: activating)
    }

    /// Each window reads its scope's conversations through a store of its own.
    private func makeEntry(scope: UUID?, key: String) -> Entry {
        let history = ChatHistoryStore(directory: AppPaths.applicationSupport())
        // Scoped to the default chat from birth, so setting that scope later would never load it.
        history.load()
        let chat = AIChatState(history: history)
        let coordinator = AIChatCoordinator(
            chat: chat, history: history, scope: .pinned(scope), settings: core.settings,
            appIndex: core.appIndex, palette: core.palette,
            paletteCoordinator: core.paletteCoordinator,
            settingsCoordinator: core.settingsCoordinator, core: core)
        let session = AIChatWindowSession(
            key: key, scope: scope, chat: chat, history: history, coordinator: coordinator,
            aiSettings: core.aiSettings)
        let window = AppWindowController(
            title: "AI Chat", contentSize: Theme.Size.aiChatWindow,
            minimumSize: Theme.Size.aiChatWindowMinimum, resizable: true,
            autosaveName: Self.autosaveName(for: key), activation: core.activationPolicy)
        window.onClose = { [weak self] in self?.didClose(key: key) }
        return Entry(session: session, window: window)
    }

    /// The red button, ⌘W and a programmatic close all land here; replies stop with the window.
    private func didClose(key: String) {
        guard let entry = windows.removeValue(forKey: key) else { return }
        entry.session.chat.cancel()
        if !isQuitting { persist() }
    }

    private func persist() {
        let items = windows.keys.sorted().map { key in
            PersistedWindow(
                scope: key, allSpaces: showsOnAllSpaces(key: key), keepInFront: keepsInFront(key: key))
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: Self.persistenceKey)
    }

    private func loadPersisted() -> [PersistedWindow] {
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
            let items = try? JSONDecoder().decode([PersistedWindow].self, from: data)
        else { return [] }
        return items
    }

    private static func key(for scope: UUID?) -> String {
        scope?.uuidString ?? "default"
    }

    /// A defaults-safe autosave key: AppKit stores the frame under "NSWindow Frame <name>".
    private static func autosaveName(for key: String) -> String {
        let slug = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return "OnecastAIChatSidebarWindow-" + String(slug)
    }
}

/// A plain sidebar split, so collapsing and the divider are AppKit's own and autosave themselves.
final class AIChatSplitViewController: NSSplitViewController {
    init(sidebar: some View, detail: some View) {
        super.init(nibName: nil, bundle: nil)
        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: sidebar))
        sidebarItem.minimumThickness = Theme.Size.aiChatSidebarMinimum
        sidebarItem.maximumThickness = Theme.Size.aiChatSidebarMaximum
        sidebarItem.canCollapse = true
        let detailHosting = NSHostingController(rootView: detail)
        detailHosting.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detailHosting)
        detailItem.minimumThickness = Theme.Size.aiChatDetailMinimum
        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        splitView.autosaveName = "OnecastAIChatSplitView"
    }

    /// AppKit would focus the sidebar's search, its first key view; typing belongs in the composer.
    override func viewDidAppear() {
        super.viewDidAppear()
        // Next turn: the hosted SwiftUI tree has not built its text field yet.
        DispatchQueue.main.async { [weak self] in
            guard let detail = self?.splitViewItems.last?.viewController.view,
                let composer = Self.editableText(in: detail)
            else { return }
            detail.window?.makeFirstResponder(composer)
        }
    }

    /// The detail pane's one editable text control is its composer.
    private static func editableText(in view: NSView) -> NSView? {
        if let field = view as? NSTextField, field.isEditable { return field }
        if let text = view as? NSTextView, text.isEditable { return text }
        for subview in view.subviews {
            if let found = editableText(in: subview) { return found }
        }
        return nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

extension View {
    /// What the window's views read: the theme, the palette's own model menu, and the metrics.
    func windowEnvironment(_ core: AppCore) -> some View {
        environment(core.settings)
            .environment(core.palette)
            .environment(\.metrics, core.settings.interfaceSize.metrics)
    }
}
