import Foundation

/// A third-party DockWidget's `manifest.json`, readable before its code is built.
struct DockWidgetManifest: Codable, Sendable, Hashable {
    static let defaultIcon = "square.grid.2x2"
    static let defaultCategory = "Other"
    /// A widget id starting with this is a first-party one, so no manifest may claim it.
    static let reservedPrefix = "builtin."

    let name: String
    let identifier: String
    var subtitle: String
    var icon: String
    var category: String
    /// The sizes the widget draws well at; the first is the size a new instance takes.
    var sizes: [DockWidgetSpan]
    /// The Swift `-module-name` to compile under. Absent: derived from `name`.
    var module: String?
    /// Per-instance settings; the dock editor shows one control each.
    var preferences: [PluginPreference]?

    init(
        name: String, identifier: String, subtitle: String = "", icon: String = defaultIcon,
        category: String = defaultCategory, sizes: [DockWidgetSpan] = [.compact],
        module: String? = nil, preferences: [PluginPreference]? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.sizes = sizes.isEmpty ? [.compact] : sizes
        self.module = module
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey {
        case name, identifier, subtitle, icon, category, sizes, module, preferences
    }

    /// Only `name` and `identifier` are required; an unknown size is dropped, not an error.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        identifier = try c.decode(String.self, forKey: .identifier)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        icon = Self.nonBlank(try c.decodeIfPresent(String.self, forKey: .icon)) ?? Self.defaultIcon
        category =
            Self.nonBlank(try c.decodeIfPresent(String.self, forKey: .category))
            ?? Self.defaultCategory
        let raw = (try? c.decodeIfPresent([String].self, forKey: .sizes)) ?? []
        var seen = Set<DockWidgetSpan>()
        let known = raw.compactMap(DockWidgetSpan.init(rawValue:)).filter { seen.insert($0).inserted }
        sizes = known.isEmpty ? [.compact] : known
        module = try c.decodeIfPresent(String.self, forKey: .module)
        preferences = try c.decodeIfPresent([PluginPreference].self, forKey: .preferences)
    }

    /// Whether the identifier can key a dock item: non-blank and not a first-party id.
    var hasUsableIdentifier: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty
            && !identifier.hasPrefix(Self.reservedPrefix)
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return text
    }
}
