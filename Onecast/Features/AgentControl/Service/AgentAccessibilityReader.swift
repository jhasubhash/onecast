#if DEBUG
import AppKit
@preconcurrency import ApplicationServices

/// The AX API on our own pid, where SwiftUI serves its tree; AppKit answers inline, so main only.
@MainActor
enum AgentAccessibilityReader {
    struct Options: Sendable {
        var includeContent = false
        /// The clipboard's rows are copied text: the palette's and its menu's text becomes a length.
        var redactsPaletteText = false
        var pruned = true
    }

    struct WindowTree: Sendable {
        let key: WindowKey
        let elements: [AgentElement]
    }

    /// Where a window lives in AX terms; a second dock shares the identifier but not the frame.
    struct WindowKey: Equatable, Sendable {
        /// Nil when unnamed, as the AX side reads an empty identifier.
        let identifier: String?
        let frame: AgentSnapshot.Rect?
    }

    enum PressOutcome: Sendable {
        case pressed(role: String)
        case notFound
        case refused
    }

    /// Bounds one window's walk: a long list must not flood the reply.
    private static let maximumNodes = 2000
    private static let maximumDepth = 60
    /// Bounds a read some view answers slowly; in-process there is no other thread to wait on.
    private static let messagingTimeout: Float = 2

    /// Strings, not `CFString`s: a static `[CFString]` is not `Sendable`.
    private static let attributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, "AXIdentifier", kAXDescriptionAttribute,
        kAXTitleAttribute, kAXValueAttribute, kAXSelectedAttribute, kAXEnabledAttribute,
        kAXFocusedAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
    ]

    /// Walks only the windows `keys` names: a tree is the costly part of a read.
    static func windows(_ keys: [WindowKey], options: Options) -> [WindowTree] {
        guard !keys.isEmpty else { return [] }
        return axWindows(of: application).compactMap { window in
            let node = read(window, options: options, redacts: false)
            let key = WindowKey(identifier: node.identifier, frame: node.frame)
            guard keys.contains(key) else { return nil }
            let redacts =
                options.redactsPaletteText
                && ["onecast.palette", "onecast.menu"].contains(node.identifier ?? "")
            var budget = maximumNodes
            let raw = children(of: window, depth: 0, budget: &budget, options: options, redacts)
            return WindowTree(key: key, elements: options.pruned ? AgentElement.pruned(raw) : raw)
        }
    }

    static func press(_ match: String, in key: WindowKey?) -> PressOutcome {
        for window in axWindows(of: application) {
            if let key {
                let node = read(window, options: Options(), redacts: false)
                guard WindowKey(identifier: node.identifier, frame: node.frame) == key else { continue }
            }
            var budget = maximumNodes
            guard let found = find(match, under: window, depth: 0, budget: &budget) else {
                continue
            }
            let role = read(found, options: Options(), redacts: false).role
            let result = AXUIElementPerformAction(found, kAXPressAction as CFString)
            return result == .success ? .pressed(role: role) : .refused
        }
        return .notFound
    }

    private static var application: AXUIElement {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        return application
    }

    private static func axWindows(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func children(
        of element: AXUIElement, depth: Int, budget: inout Int, options: Options, _ redacts: Bool
    ) -> [AgentElement] {
        guard depth < maximumDepth else { return [] }
        var result: [AgentElement] = []
        for child in childElements(of: element) {
            guard budget > 0 else { break }
            budget -= 1
            var node = read(child, options: options, redacts: redacts)
            let grandchildren = children(
                of: child, depth: depth + 1, budget: &budget, options: options, redacts)
            node.children = grandchildren.isEmpty ? nil : grandchildren
            result.append(node)
        }
        return result
    }

    private static func find(
        _ match: String, under element: AXUIElement, depth: Int, budget: inout Int
    ) -> AXUIElement? {
        guard depth < maximumDepth else { return nil }
        for child in childElements(of: element) {
            guard budget > 0 else { return nil }
            budget -= 1
            let node = read(child, options: Options(includeContent: true), redacts: false)
            let names = [node.identifier, node.label, node.title]
            if names.contains(where: { $0?.caseInsensitiveCompare(match) == .orderedSame }) {
                return child
            }
            if let found = find(match, under: child, depth: depth + 1, budget: &budget) {
                return found
            }
        }
        return nil
    }

    private static func childElements(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// One round trip for every attribute; a missing one comes back as an AXValue error, skipped.
    private static func read(
        _ element: AXUIElement, options: Options, redacts: Bool
    ) -> AgentElement {
        var values: CFArray?
        AXUIElementCopyMultipleAttributeValues(
            element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        let list = (values as? [Any]) ?? []
        func value(_ index: Int) -> Any? {
            guard index < list.count else { return nil }
            let item = list[index] as CFTypeRef
            if CFGetTypeID(item) == AXValueGetTypeID(),
                AXValueGetType(item as! AXValue) == .axError  // swiftlint:disable:this force_cast
            {
                return nil
            }
            return list[index]
        }
        let role = value(0) as? String ?? "AXUnknown"
        let hidesText = redacts && role != "AXButton"
        let hidesValue = hidesText || (!options.includeContent && role == "AXTextArea")
        return AgentElement(
            role: role,
            subrole: nonEmpty(value(1) as? String),
            identifier: nonEmpty(value(2) as? String),
            label: masked(nonEmpty(value(3) as? String), if: hidesText),
            title: masked(nonEmpty(value(4) as? String), if: hidesText),
            value: masked(string(value(5)), if: hidesValue),
            selected: (value(6) as? Bool) == true ? true : nil,
            enabled: (value(7) as? Bool) == false ? false : nil,
            focused: (value(8) as? Bool) == true ? true : nil,
            frame: frame(position: value(9), size: value(10)))
    }

    private static func frame(position: Any?, size: Any?) -> AgentSnapshot.Rect? {
        guard let position, let size else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
            // swiftlint:disable:next force_cast
            AXValueGetValue(size as! AXValue, .cgSize, &extent), extent.width > 0
        else { return nil }
        return AgentSnapshot.Rect(
            x: origin.x, y: origin.y, width: extent.width, height: extent.height)
    }

    private static func masked(_ text: String?, if hides: Bool) -> String? {
        guard hides, let text else { return text }
        return "‹\(text.count) chars›"
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return nonEmpty(text)
        case let text as NSAttributedString: return nonEmpty(text.string)
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
#endif
