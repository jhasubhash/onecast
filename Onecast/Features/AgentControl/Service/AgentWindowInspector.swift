#if DEBUG
import AppKit

/// The app's visible windows as data, each joined to its AX tree when asked for elements.
@MainActor
enum AgentWindowInspector {
    static func windows(
        includeElements: Bool, options: AgentAccessibilityReader.Options
    ) -> [AgentSnapshot.Window] {
        let trees = includeElements ? AgentAccessibilityReader.windows(options: options) : []
        return identified().map { id, window in
            var snapshot = describe(window, id: id)
            guard includeElements else { return snapshot }
            let key = self.key(of: window)
            snapshot.elements =
                trees.first { $0.identifier == key.identifier && $0.frame == key.frame }?.elements
            return snapshot
        }
    }

    /// Visible windows with ids unique among them: a second dock is `dock#2`.
    static func identified() -> [(id: String, window: NSWindow)] {
        var seen: [String: Int] = [:]
        return NSApp.windows.filter(\.isVisible).map { window in
            let base = id(of: window)
            let count = seen[base, default: 0] + 1
            seen[base] = count
            return (count == 1 ? base : "\(base)#\(count)", window)
        }
    }

    static func window(id: String) -> NSWindow? {
        identified().first { $0.id == id }?.window
    }

    /// How the AX API names this window, to find its tree there.
    static func key(of window: NSWindow) -> AgentAccessibilityReader.WindowKey {
        AgentAccessibilityReader.WindowKey(
            identifier: window.accessibilityIdentifier(), frame: rect(window.frame))
    }

    static func describe(_ window: NSWindow, id: String) -> AgentSnapshot.Window {
        AgentSnapshot.Window(
            id: id, title: window.accessibilityTitle() ?? window.title,
            className: String(describing: type(of: window)), level: window.level.rawValue,
            isKey: window.isKeyWindow, isVisible: window.isVisible, frame: rect(window.frame))
    }

    /// The `onecast.` identifier without its prefix, else the title, else the class name.
    static func id(of window: NSWindow) -> String {
        let identifier = window.accessibilityIdentifier()
        if identifier.hasPrefix("onecast.") { return String(identifier.dropFirst("onecast.".count)) }
        if !identifier.isEmpty { return identifier }
        if !window.title.isEmpty { return window.title }
        return String(describing: type(of: window))
    }

    /// AppKit frames are bottom-left on the primary display; AX and a driver use top-left points.
    static func rect(_ frame: NSRect) -> AgentSnapshot.Rect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return AgentSnapshot.Rect(
            x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
#endif
