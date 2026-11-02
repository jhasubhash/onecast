import Foundation

extension HotKeyAction {
    /// `Assistant.entryID`'s prefix, restated so this file needs none of the AI model.
    private static let assistantPrefix = "assistant:"

    /// A row's action from its ID alone; apps and panes are keyed by bundle ID instead.
    init?(entryID: String) {
        if let command = CommandID(rawValue: entryID) {
            guard let action = command.hotKeyAction else { return nil }
            self = action
        } else if let action = SystemActionCatalog.action(forEntryID: entryID) {
            self = .systemAction(id: action.id)
        } else if let command = WindowCommandCatalog.command(forEntryID: entryID) {
            self = .windowCommand(id: command.id)
        } else if let id = CustomWindowSize.id(fromEntryID: entryID) {
            self = .customWindowSize(id: id)
        } else if let id = WindowLayout.id(fromEntryID: entryID) {
            self = .windowLayout(id: id)
        } else if let id = CustomQuickAction.id(fromEntryID: entryID) {
            self = .quickAction(id: id)
        } else if let id = CustomCommand.id(fromEntryID: entryID) {
            self = .customCommand(id: id)
        } else if let id = Quicklink.id(fromEntryID: entryID) {
            self = .quicklink(id: id)
        } else if let id = AppleShortcut.id(fromEntryID: entryID) {
            self = .appleShortcut(id: id)
        } else if let id = StoredSnippet.id(fromEntryID: entryID) {
            self = .snippet(id: id)
        } else if entryID.hasPrefix(Self.assistantPrefix),
            let id = UUID(uuidString: String(entryID.dropFirst(Self.assistantPrefix.count)))
        {
            self = .assistant(id: id)
        } else if let id = ScheduledTask.id(fromEntryID: entryID) {
            self = .scheduledTask(id: id)
        } else {
            return nil
        }
    }

    /// The inverse of `init?(entryID:)`; nil for the actions no row ID names.
    var entryID: String? {
        switch self {
        case .command(let id): id.hotKeyAction == nil ? nil : id.rawValue
        case .systemAction(let id): SystemActionCatalog.action(id: id).entryID
        case .windowCommand(let id): WindowCommandCatalog.command(id: id)?.entryID
        case .customWindowSize(let id): CustomWindowSize.entryIDPrefix + id.uuidString.lowercased()
        case .windowLayout(let id): WindowLayout.entryIDPrefix + id.uuidString.lowercased()
        case .quickAction(let id): CustomQuickAction.entryIDPrefix + id.uuidString.lowercased()
        case .customCommand(let id): CustomCommand.entryIDPrefix + id.uuidString.lowercased()
        case .quicklink(let id): Quicklink.entryIDPrefix + id.uuidString.lowercased()
        case .appleShortcut(let id): AppleShortcut.entryID(for: id)
        case .snippet(let id): StoredSnippet.entryIDPrefix + id
        case .assistant(let id): Self.assistantPrefix + id.uuidString
        case .scheduledTask(let id): ScheduledTask.entryIDPrefix + id.uuidString.lowercased()
        // Extension, plugin and dock rows keep the links their own features build.
        case .togglePalette, .toggleAIBar, .dictation, .app, .settingsPane, .extensionCommand,
            .pluginCommand, .dockSetup, .dockVisibility:
            nil
        }
    }
}
