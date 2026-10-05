import Foundation

/// A running app as the dock needs it; the effect layer reads it from `NSWorkspace`.
struct DockRunningApp: Sendable, Hashable {
    var bundleID: String?
    var path: String
    var name: String
    var processID: Int32
    var isActive: Bool
    var isHidden: Bool
}

/// A minimized window, offered as its own tile before the Trash.
struct DockMinimizedWindow: Sendable, Hashable {
    /// Opaque to this layer; the effect layer maps it back to its accessibility element.
    var token: String
    var title: String
    var appName: String
    var bundleID: String?
    var appPath: String
}

/// One position in a dock as drawn, after running apps, minimized windows and Trash join in.
enum DockSlot: Sendable, Hashable, Identifiable {
    case pinned(DockItem, running: DockRunningApp?)
    /// A running app with no pinned item of its own.
    case running(DockRunningApp)
    case minimized(DockMinimizedWindow)
    case divider(String)
    case trash

    var id: String {
        switch self {
        case .pinned(let item, _): "item:\(item.id.uuidString)"
        case .running(let app): "running:\(app.processID)"
        case .minimized(let window): "minimized:\(window.token)"
        case .divider(let name): "divider:\(name)"
        case .trash: "trash"
        }
    }

    var extent: DockGeometry.Extent {
        switch self {
        case .pinned(let item, _):
            switch item.kind {
            case .spacer(let size): .spacer(size)
            case .widget(let widget): widget.span == .compact ? .tile : .span(widget.span.tiles)
            default: .tile
            }
        case .running, .minimized, .trash: .tile
        case .divider: .divider
        }
    }
}

enum DockSlots {
    /// The dock's drawn order: pinned items, then unpinned running apps, then minimized windows
    /// and Trash, each group after a divider only when the group is non-empty.
    static func arrange(
        items: [DockItem], running: [DockRunningApp], minimized: [DockMinimizedWindow],
        options: DockContentOptions
    ) -> [DockSlot] {
        var unclaimed = options.showsRunningApps ? running : []
        var slots: [DockSlot] = items.map { item in
            guard case .app(let reference) = item.kind else { return .pinned(item, running: nil) }
            // Every pinned item reports running, but only the first claims the app's slot.
            let match = running.first { matches(reference, $0) }
            if let match { unclaimed.removeAll { $0.processID == match.processID } }
            return .pinned(item, running: match)
        }
        if !unclaimed.isEmpty {
            if !slots.isEmpty { slots.append(.divider("running")) }
            slots += unclaimed.map(DockSlot.running)
        }
        let windows = options.showsMinimizedWindows ? minimized : []
        if !windows.isEmpty || options.showsTrash {
            if !slots.isEmpty { slots.append(.divider("trailing")) }
            slots += windows.map(DockSlot.minimized)
            if options.showsTrash { slots.append(.trash) }
        }
        return slots
    }

    /// The bundle identifier decides when both sides have one, so a moved app still matches.
    static func matches(_ reference: DockAppReference, _ app: DockRunningApp) -> Bool {
        if let pinned = reference.bundleID, let running = app.bundleID {
            return pinned == running
        }
        return standardized(reference.path) == standardized(app.path)
    }

    /// Moves the item at `source` to sit before the item now at `destination`.
    static func move(_ items: [DockItem], from source: Int, to destination: Int) -> [DockItem] {
        guard items.indices.contains(source), (0...items.count).contains(destination),
            source != destination, source + 1 != destination
        else { return items }
        var result = items
        let item = result.remove(at: source)
        result.insert(item, at: destination > source ? destination - 1 : destination)
        return result
    }

    private static func standardized(_ path: String) -> String {
        var value = (path as NSString).standardizingPath
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
