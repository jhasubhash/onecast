import Foundation

/// One tile of the macOS Dock's accessibility list, decoded to plain values.
struct DockBadgeItem: Sendable, Equatable {
    var subrole: String?
    /// `AXStatusLabel`: the badge text, absent when the tile shows none.
    var statusLabel: String?
    var url: URL?
}

enum DockBadges {
    static let applicationSubrole = "AXApplicationDockItem"

    /// Bundle ID → badge text for the app tiles that show one; `bundleID` maps a tile's URL.
    static func badges(
        from items: [DockBadgeItem], bundleID: (URL) -> String?
    ) -> [String: String] {
        var badges: [String: String] = [:]
        for item in items where item.subrole == applicationSubrole {
            guard let label = item.statusLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
                !label.isEmpty, let url = item.url, let id = bundleID(url), badges[id] == nil
            else { continue }
            badges[id] = label
        }
        return badges
    }
}
