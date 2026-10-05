@preconcurrency import ApplicationServices
import AppKit

/// Reads badge labels off the macOS Dock's accessibility tree, which it keeps while hidden.
enum DockBadgeAccess {
    private static let dockBundleID = "com.apple.dock"
    private static let statusLabelAttribute = "AXStatusLabel"

    struct Reading: Sendable {
        var badges: [String: String]
        /// Every tile URL's bundle ID so far, handed back in so a bundle is opened once.
        var resolved: [URL: String]
    }

    /// Nil when the Dock cannot be read right now, so the caller keeps what it last showed.
    static func read(resolved: [URL: String]) -> Reading? {
        guard
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID)
                .first(where: { !$0.isTerminated })
        else { return nil }
        let application = AXWindowAccess.application(for: dock.processIdentifier)
        let lists = children(of: application).filter {
            AXWindowAccess.string($0, kAXRoleAttribute) == (kAXListRole as String)
        }
        guard !lists.isEmpty else { return nil }

        var resolved = resolved
        let items = lists.flatMap(children).map(item)
        let badges = DockBadges.badges(from: items) { url in
            if let known = resolved[url] { return known }
            guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
            resolved[url] = id
            return id
        }
        return Reading(badges: badges, resolved: resolved)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                == .success,
            let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func item(_ element: AXUIElement) -> DockBadgeItem {
        AXUIElementSetMessagingTimeout(element, DockWindowAccess.sweepTimeout)
        let names = [kAXSubroleAttribute, statusLabelAttribute, kAXURLAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &values) == .success,
            let values = values as? [Any], values.count == 3
        else { return DockBadgeItem() }
        // A missing attribute comes back as an AXValue error marker, which no cast here matches.
        return DockBadgeItem(
            subrole: values[0] as? String, statusLabel: values[1] as? String,
            url: values[2] as? URL)
    }
}
