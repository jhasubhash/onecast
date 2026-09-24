import AppKit
import Observation

/// The AI Chat window's toolbar, title and shortcuts: sidebar, New Chat, Find in Chat and Actions.
@MainActor
final class AIChatWindowChrome: NSObject, WindowChrome, NSToolbarDelegate, NSSearchFieldDelegate {
    private let session: AIChatWindowSession
    private unowned let controller: AIChatWindowController
    private weak var window: NSWindow?
    private var keyMonitor: Any?
    private weak var searchItem: NSSearchToolbarItem?
    private weak var actionsButton: NSButton?

    private static let newChat = NSToolbarItem.Identifier("OnecastAIChatNewChat")
    private static let search = NSToolbarItem.Identifier("OnecastAIChatSearch")
    private static let actions = NSToolbarItem.Identifier("OnecastAIChatActions")

    init(session: AIChatWindowSession, controller: AIChatWindowController) {
        self.session = session
        self.controller = controller
    }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func install(in window: NSWindow) {
        self.window = window
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        // A drag in the transcript selects text; it must never move the window instead.
        window.isMovableByWindowBackground = false
        let toolbar = NSToolbar(identifier: "OnecastAIChatToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        installKeyMonitor()
        observeTitle()
    }

    // MARK: - Title

    /// The window always names the chat on screen: its rename, generated title, or first question.
    private func observeTitle() {
        withObservationTracking {
            window?.title = session.coordinator.title(of: session.chat.session)
            _ = session.history.conversations
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, Self.newChat, .sidebarTrackingSeparator, .flexibleSpace, Self.search, Self.actions]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.newChat:
            return button(
                identifier, symbol: "square.and.pencil", label: "New Chat", tooltip: "New Chat  ⌘N",
                action: #selector(newChat))
        case Self.actions:
            let item = button(
                identifier, symbol: "slider.horizontal.3", label: "Actions", tooltip: "Actions  ⌘K",
                action: #selector(showActions))
            actionsButton = item.view as? NSButton
            return item
        case Self.search:
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.searchField.placeholderString = "Find in Chat"
            item.searchField.delegate = self
            item.toolTip = "Find in Chat  ⌘F"
            item.preferredWidthForSearchField = 220
            searchItem = item
            return item
        default:
            return nil
        }
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier, symbol: String, label: String, tooltip: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
            target: self, action: action)
        button.bezelStyle = .toolbar
        item.view = button
        item.label = label
        item.toolTip = tooltip
        return item
    }

    @objc private func newChat() {
        session.newChat()
    }

    @objc private func showActions() {
        let menu = actionsMenu()
        if let button = actionsButton {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else if let content = window?.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: content.bounds.maxX - 40, y: content.bounds.maxY), in: content)
        }
    }

    // MARK: - Find

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        session.find.query = field.stringValue
    }

    /// Return and ⇧Return walk the matches from inside the field, as every Mac Find field does.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let backwards = NSEvent.modifierFlags.contains(.shift)
        session.stepFind(backwards ? -1 : 1)
        return true
    }

    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        session.find.query = ""
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.isKeyWindow
            else { return event }
            return self.handle(event, in: window) ? nil : event
        }
    }

    private func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !event.isARepeat, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        let chat = session.chat
        switch (modifiers, key) {
        case ([.command], "f"):
            searchItem?.beginSearchInteraction()
        case ([.command], "g"):
            session.stepFind(1)
        case ([.command, .shift], "g"):
            session.stepFind(-1)
        case ([.command], "k"):
            showActions()
        case ([.command], "n"):
            session.newChat()
        case ([.command], "r"):
            guard session.coordinator.canRegenerate else { return false }
            session.coordinator.regenerate()
        case ([.command, .shift], "c"):
            guard chat.lastAssistantText != nil else { return false }
            session.coordinator.copyLastResponse()
        case ([.command], "."):
            guard chat.isStreaming else { return false }
            session.coordinator.stopResponse()
        case ([.command], "c"):
            // A reply's selection leaves the keyboard in the composer, so its ⌘C is answered here.
            let editor = window.firstResponder as? NSTextView
            guard (editor?.selectedRange().length ?? 0) == 0 else { return false }
            return MarkdownTextView.copySelection(in: window)
        default:
            return false
        }
        return true
    }

    // MARK: - Actions menu

    private func actionsMenu() -> NSMenu {
        let menu = NSMenu()
        let chat = session.chat
        let coordinator = session.coordinator
        let id = chat.session.id
        let saved = session.history.conversation(id: id) != nil
        if chat.isStreaming {
            menu.addItem(item("Stop Response", "stop.fill", key: ".") { coordinator.stopResponse() })
        }
        menu.addItem(item("New Chat", "square.and.pencil", key: "n") { [session] in session.newChat() })
        if coordinator.canRegenerate {
            menu.addItem(item("Regenerate Response", "arrow.clockwise", key: "r") { coordinator.regenerate() })
        }
        menu.addItem(.separator())
        if chat.lastAssistantText != nil {
            menu.addItem(
                item("Copy Last Response", "doc.on.doc", key: "c", modifiers: [.command, .shift]) {
                    coordinator.copyLastResponse()
                })
        }
        if saved {
            menu.addItem(item("Copy Chat", "doc.on.clipboard") { coordinator.copyChat(id: id) })
            menu.addItem(item("Export as Markdown…", "square.and.arrow.up") { coordinator.exportChat(id: id) })
            menu.addItem(.separator())
            let pinned = coordinator.isPinned(id: id)
            menu.addItem(
                item(pinned ? "Unpin Chat" : "Pin Chat", pinned ? "pin.slash" : "pin") {
                    coordinator.togglePin(id: id)
                })
            menu.addItem(
                item("Delete Chat…", "trash") { [session] in
                    Task { @MainActor in
                        guard await coordinator.confirmDelete(id: id) else { return }
                        session.delete(id: id)
                    }
                })
        }
        menu.addItem(.separator())
        menu.addItem(item("Find in Chat", "magnifyingglass", key: "f") { [weak self] in
            self?.searchItem?.beginSearchInteraction()
        })
        let key = session.key
        let allSpaces = controller.showsOnAllSpaces(key: key)
        let spacesTitle = allSpaces ? "Show on This Space Only" : "Show on All Spaces"
        menu.addItem(
            item(spacesTitle, "square.on.square") { [weak controller] in
                controller?.setShowsOnAllSpaces(!allSpaces, key: key)
            })
        let inFront = controller.keepsInFront(key: key)
        let frontTitle = inFront ? "Don't Keep in Front" : "Keep in Front of Other Apps"
        menu.addItem(
            item(frontTitle, inFront ? "pin.slash" : "pin") { [weak controller] in
                controller?.setKeepsInFront(!inFront, key: key)
            })
        menu.addItem(.separator())
        menu.addItem(item("AI Settings", "gearshape") { coordinator.showSettings() })
        return menu
    }

    private func item(
        _ title: String, _ symbol: String, key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command], action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        item.keyEquivalentModifierMask = modifiers
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}

/// A menu row that runs a closure; the key equivalent only labels the shortcut the monitor handles.
@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, keyEquivalent: String, action: @escaping @MainActor () -> Void) {
        run = action
        super.init(title: title, action: #selector(runAction), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func runAction() {
        run()
    }
}
