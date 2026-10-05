// Standalone contract tests for reading the macOS Dock's badge labels.
import Foundation

@main
@MainActor
struct DockBadgesTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static let ids: [String: String] = [
        "file:///Applications/Mail.app/": "com.apple.mail",
        "file:///Applications/Slack.app/": "com.tinyspeck.slackmacgap",
        "file:///Applications/Copy%201.app/": "com.example.copy",
        "file:///Applications/Copy%202.app/": "com.example.copy"
    ]

    static func item(_ subrole: String?, _ label: String?, _ url: String?) -> DockBadgeItem {
        DockBadgeItem(subrole: subrole, statusLabel: label, url: url.flatMap(URL.init(string:)))
    }

    static func badges(_ items: [DockBadgeItem]) -> [String: String] {
        DockBadges.badges(from: items) { ids[$0.absoluteString] }
    }

    static func main() {
        mapsLabelsToBundleIDs()
        ignoresTilesWithoutBadges()
        ignoresNonAppTiles()
        ignoresUnresolvableTiles()
        firstTileWinsForOneBundle()
        keepsDotsAndTrimsLabels()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func mapsLabelsToBundleIDs() {
        let result = badges([
            item(DockBadges.applicationSubrole, "4868", "file:///Applications/Mail.app/"),
            item(DockBadges.applicationSubrole, "3", "file:///Applications/Slack.app/")
        ])
        expect(
            result == ["com.apple.mail": "4868", "com.tinyspeck.slackmacgap": "3"],
            "each labelled app tile maps its bundle ID to its label")
    }

    static func ignoresTilesWithoutBadges() {
        let result = badges([
            item(DockBadges.applicationSubrole, nil, "file:///Applications/Mail.app/"),
            item(DockBadges.applicationSubrole, "", "file:///Applications/Slack.app/"),
            item(DockBadges.applicationSubrole, "  ", "file:///Applications/Slack.app/")
        ])
        expect(result.isEmpty, "a missing, empty or blank label is no badge")
    }

    static func ignoresNonAppTiles() {
        let result = badges([
            item("AXFolderDockItem", "2", "file:///Applications/Mail.app/"),
            item("AXHandoffDockItem", "com.apple.iphone", nil),
            item(nil, "9", "file:///Applications/Slack.app/")
        ])
        expect(result.isEmpty, "only application tiles carry a badge")
    }

    static func ignoresUnresolvableTiles() {
        let result = badges([
            item(DockBadges.applicationSubrole, "1", nil),
            item(DockBadges.applicationSubrole, "1", "file:///Applications/Unknown.app/")
        ])
        expect(result.isEmpty, "a tile with no URL or no bundle ID cannot be mapped")
    }

    static func firstTileWinsForOneBundle() {
        let result = badges([
            item(DockBadges.applicationSubrole, "5", "file:///Applications/Copy%201.app/"),
            item(DockBadges.applicationSubrole, "6", "file:///Applications/Copy%202.app/")
        ])
        expect(result == ["com.example.copy": "5"], "two tiles of one bundle keep the first label")
    }

    static func keepsDotsAndTrimsLabels() {
        let result = badges([
            item(DockBadges.applicationSubrole, " • ", "file:///Applications/Slack.app/")
        ])
        expect(result == ["com.tinyspeck.slackmacgap": "•"], "a dot badge survives, trimmed")
    }
}
