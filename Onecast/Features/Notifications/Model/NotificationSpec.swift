import Foundation

struct NotificationSpec: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var body: String
    var style: NotificationStyle
    var corner: NotificationCorner
    var dwell: TimeInterval?          // nil = sticky until dismissed
    var actions: [NotificationAction]
    /// Nil is the neutral card; saved tasks from before colour existed decode as exactly that.
    var tint: NotificationTint?
}

enum NotificationStyle: String, Codable, Sendable, CaseIterable {
    case toast, banner, card
}

enum NotificationCorner: String, Codable, Sendable, CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

/// A named accent, not a free colour: every one stays legible on the glass card in both appearances.
enum NotificationTint: String, Codable, Sendable, CaseIterable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray

    /// A colour word as someone would say it; the common synonyms fold onto the nearest case.
    init?(word: String) {
        let key = word.lowercased()
        if let exact = Self(rawValue: key) {
            self = exact
        } else if let alias = Self.synonyms[key] {
            self = alias
        } else {
            return nil
        }
    }

    private static let synonyms: [String: NotificationTint] = [
        "grey": .gray, "violet": .purple, "lavender": .purple, "magenta": .pink, "rose": .pink,
        "crimson": .red, "scarlet": .red, "amber": .orange, "gold": .yellow, "golden": .yellow,
        "lime": .green, "emerald": .green, "cyan": .teal, "turquoise": .teal, "aqua": .teal,
        "navy": .blue, "indigo": .blue, "silver": .gray,
    ]

    /// Every word `init(word:)` accepts, for a caller building a matcher over free text.
    static let spokenWords: [String] = allCases.map(\.rawValue) + synonyms.keys.sorted()
}

struct NotificationAction: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
}
