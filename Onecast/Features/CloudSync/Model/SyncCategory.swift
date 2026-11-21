import Foundation

/// What the iCloud Sync pane lists; each optional one is a per-Mac choice, on by default.
enum SyncCategory: String, CaseIterable, Codable, Sendable {
    case aiCommands, dictation, mcpServers, quicklinks, notes, snippets, windowLayouts
    case extensions
    case launchAtLogin, showInMenuBar, appearance, interfaceSize, windowMode
    case hotkeysAndAliases, favoritesAndFallbacks, otherSettings

    enum Group: CaseIterable, Sendable {
        case content, general, always
    }

    var group: Group {
        switch self {
        case .aiCommands, .dictation, .mcpServers, .quicklinks, .notes, .snippets,
            .windowLayouts, .extensions:
            .content
        case .launchAtLogin, .showInMenuBar, .appearance, .interfaceSize, .windowMode: .general
        case .hotkeysAndAliases, .favoritesAndFallbacks, .otherSettings: .always
        }
    }

    var isOptional: Bool { group != .always }

    /// Whether the pane counts its items; a setting is one value, not a collection.
    var isCounted: Bool {
        switch self {
        case .aiCommands, .mcpServers, .quicklinks, .notes, .snippets, .extensions: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .aiCommands: "AI Commands"
        case .dictation: "Dictation"
        case .mcpServers: "MCP Servers"
        case .quicklinks: "Quicklinks"
        case .notes: "Notes"
        case .snippets: "Snippets"
        case .windowLayouts: "Window Layouts"
        case .extensions: "Extensions"
        case .launchAtLogin: "Open at Login"
        case .showInMenuBar: "Show in Menu Bar"
        case .appearance: "Appearance"
        case .interfaceSize: "Interface Size"
        case .windowMode: "Window Mode"
        case .hotkeysAndAliases: "Hotkeys & Aliases"
        case .favoritesAndFallbacks: "Favorites & Fallback Order"
        case .otherSettings: "Other Settings"
        }
    }

    var symbol: String {
        switch self {
        case .aiCommands: "sparkles"
        case .dictation: "mic"
        case .mcpServers: "server.rack"
        case .quicklinks: "link"
        case .notes: "note.text"
        case .snippets: "text.badge.plus"
        case .windowLayouts: "rectangle.split.2x2"
        case .extensions: "puzzlepiece.extension"
        case .launchAtLogin: "power"
        case .showInMenuBar: "menubar.rectangle"
        case .appearance: "paintbrush"
        case .interfaceSize: "textformat.size"
        case .windowMode: "macwindow"
        case .hotkeysAndAliases: "keyboard"
        case .favoritesAndFallbacks: "star"
        case .otherSettings: "gearshape"
        }
    }

    /// The pane's info tip; nil where the title says it all.
    var detail: String? {
        switch self {
        case .mcpServers:
            "Credentials stay on each Mac, and a new server asks before it runs."
        case .extensions:
            """
                    Store extensions install on every Mac where Extensions is on. Passwords and file \
                    paths in their preferences stay on each Mac.
                    """
        case .dictation:
            "The model and microphone stay on each Mac."
        case .hotkeysAndAliases:
            """
                    A shortcut whose app or item isn't on a Mac yet waits until it is, and one that \
                    clashes there keeps that Mac's choice.
                    """
        case .otherSettings:
            "Feature switches, folders and language stay on each Mac."
        default: nil
        }
    }

    static func categories(in group: Group) -> [SyncCategory] {
        allCases.filter { $0.group == group }
    }
}
