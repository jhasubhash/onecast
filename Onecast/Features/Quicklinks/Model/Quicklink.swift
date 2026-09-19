import Foundation

/// A user-authored URL, search, file, folder or deeplink, surfaced as a launcher command.
struct Quicklink: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "quicklink:"
    /// Fallback glyph when there is no icon and the destination can't be detected.
    static let sfSymbol = "link"

    let id: UUID
    var name: String
    /// The raw destination template; may still contain `{argument}`-style placeholders.
    var link: String
    /// Bundle id of the app to open with, or nil for the system default handler.
    var openWithBundleID: String?
    /// SF Symbol override; nil takes the glyph the detected destination suggests.
    var iconSymbol: String?
    /// Off keeps the row and everything attached to it, but nothing may offer or open it.
    var isEnabled: Bool
    var showsInRootSearch: Bool
    /// A stamp rather than a flag, so the pinned block is ordered by *when* you pinned.
    var pinnedAt: Date?
    var createdAt: Date
    /// User-authored words that, when the typed query contains one, float this quicklink to the top
    /// of the fallback list. Normalised lowercase; empty means it is never promoted, only offered.
    var triggers: [String]

    init(
        id: UUID = UUID(), name: String, link: String, openWithBundleID: String? = nil,
        iconSymbol: String? = nil, isEnabled: Bool = true, showsInRootSearch: Bool = true,
        pinnedAt: Date? = nil, createdAt: Date = Date(), triggers: [String] = []
    ) {
        self.id = id
        self.name = name
        self.link = link
        self.openWithBundleID = openWithBundleID
        self.iconSymbol = iconSymbol
        self.isEnabled = isEnabled
        self.showsInRootSearch = showsInRootSearch
        self.pinnedAt = pinnedAt
        self.createdAt = createdAt
        self.triggers = triggers
    }

    var isPinned: Bool { pinnedAt != nil }

    /// The one glyph rule: the override, else what the detected destination suggests.
    var symbol: String {
        iconSymbol ?? QuicklinkDestination.detect(link)?.defaultSymbol ?? Self.sfSymbol
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// The one display order, sorted through by both the store and the launcher slice.
    static func precedes(_ lhs: Quicklink, _ rhs: Quicklink) -> Bool {
        switch (lhs.pinnedAt, rhs.pinnedAt) {
        case (let left?, let right?):
            return left != right ? left < right : lhs.id.uuidString < rhs.id.uuidString
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none):
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order != .orderedSame
                ? order == .orderedAscending
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // Hand-written, so an added field keeps old exports importable and imports stay minimal.
    private enum CodingKeys: String, CodingKey {
        case id, name, link, openWithBundleID, iconSymbol, isEnabled, showsInRootSearch, pinnedAt
        case createdAt, triggers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        link = try container.decode(String.self, forKey: .link)
        openWithBundleID = try container.decodeIfPresent(String.self, forKey: .openWithBundleID)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        showsInRootSearch =
            try container.decodeIfPresent(Bool.self, forKey: .showsInRootSearch) ?? true
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        triggers = try container.decodeIfPresent([String].self, forKey: .triggers) ?? []
    }

    /// Lowercased, trimmed, newline-free and de-duplicated — the one form the matcher compares
    /// against, so the store, the editor and an import all agree on what a trigger is.
    static func normalized(triggers: [String]) -> [String] {
        var seen = Set<String>()
        return
            triggers
            .map {
                $0.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces).lowercased()
            }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// What `{selection}` falls back to when the target app exposes no readable selection.
enum QuicklinkSelectionFallback: String, CaseIterable, Identifiable, Sendable {
    case ask
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask for it"
        case .clipboard: return "Use the clipboard"
        }
    }
}

enum QuicklinkError: LocalizedError, Equatable {
    case emptyName
    case emptyLink
    case duplicateName
    case unresolvableLink
    case invalidCharacter
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the quicklink."
        case .emptyLink: return "Enter a link to open."
        case .duplicateName: return "A quicklink with this name already exists."
        case .unresolvableLink:
            return "This doesn't look like a URL, file path, or deeplink."
        case .invalidCharacter: return "Names and links cannot contain null characters."
        case .storageUnavailable:
            return "The quicklinks database could not be opened, so changes can't be saved."
        }
    }
}
