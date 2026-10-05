import Foundation

/// Why reading or changing the macOS Dock failed, worded for the notice that reports it.
enum NativeDockError: LocalizedError, Equatable {
    case unreadableLayout
    case missingApps([String])
    case unwritableTiles([String])
    case writeFailed

    /// Names listed before the rest collapse into a count, so the notice stays one short read.
    static let namedLimit = 5

    var errorDescription: String? {
        switch self {
        case .unreadableLayout:
            "The macOS Dock's pinned apps couldn't be read."
        case .missingApps(let names):
            names.count == 1
                ? "\(Self.list(names)) can't be found any more. Remove it from the layout or "
                    + "reinstall it, then try again."
                : "These apps can't be found any more: \(Self.list(names)). Remove them from the "
                    + "layout or reinstall them, then try again."
        case .unwritableTiles(let types):
            "The layout has items Onecast can't write back to the macOS Dock: \(Self.list(types))."
        case .writeFailed:
            "The macOS Dock's settings couldn't be saved."
        }
    }

    private static func list(_ names: [String]) -> String {
        let shown = names.prefix(namedLimit).joined(separator: ", ")
        let rest = names.count - namedLimit
        return rest > 0 ? "\(shown) and \(rest) more" : shown
    }
}
