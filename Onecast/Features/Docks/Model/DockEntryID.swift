import Foundation

extension DockSetup {
    static let entryIDPrefix = "dock-setup:"
    static let launcherSymbol = "dock.rectangle"

    var entryID: String { Self.entryID(for: id) }

    static func entryID(for id: UUID) -> String { entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }
}

extension CustomDock {
    static let entryIDPrefix = "dock:"

    var entryID: String { Self.entryID(for: id) }

    static func entryID(for id: UUID) -> String { entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// What the launcher row offers: hiding a dock that shows, showing one that doesn't.
    var launcherTitle: String { (isVisible ? "Hide " : "Show ") + name }

    var launcherSymbol: String {
        isVisible ? "dock.arrow.down.rectangle" : "dock.arrow.up.rectangle"
    }
}
