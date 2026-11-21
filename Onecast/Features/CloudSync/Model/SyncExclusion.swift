import Foundation

enum SyncExclusion: CaseIterable, Sendable {
    case clipboardHistory, customCommands, searchRanking, credentials, macSpecific

    var title: String {
        switch self {
        case .clipboardHistory: "Clipboard History"
        case .customCommands: "Custom Commands"
        case .searchRanking: "Search Ranking"
        case .credentials: "Passwords & API Keys"
        case .macSpecific: "Mac-Specific Settings"
        }
    }

    var symbol: String {
        switch self {
        case .clipboardHistory: "doc.on.clipboard"
        case .customCommands: "terminal"
        case .searchRanking: "magnifyingglass"
        case .credentials: "key"
        case .macSpecific: "desktopcomputer"
        }
    }

    var detail: String {
        switch self {
        case .clipboardHistory:
            "What you copy stays on the Mac you copied it on."
        case .customCommands:
            "They run code, so each Mac keeps its own."
        case .searchRanking:
            "Onecast learns what you pick on each Mac, so ranking stays there."
        case .credentials:
            "API keys, server credentials and extension passwords are never synced."
        case .macSpecific:
            """
                    Feature switches, permissions, folders, language, search scopes and the palette's \
                    position stay on each Mac.
                    """
        }
    }
}
