import Foundation

/// One node of a window's accessibility tree, as read in-process and pruned for a reader.
struct AgentElement: Codable, Equatable, Sendable {
    var role: String
    var subrole: String?
    var identifier: String?
    var label: String?
    var title: String?
    var value: String?
    var selected: Bool?
    var enabled: Bool?
    var focused: Bool?
    var frame: AgentSnapshot.Rect?
    var children: [AgentElement]?

    /// True when the node says something a reader can act on, beyond being a container.
    var isInformative: Bool {
        [identifier, label, title, value].contains { !($0 ?? "").isEmpty }
            || selected == true || focused == true || Self.interactiveRoles.contains(role)
    }

    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXMenuButton", "AXSlider", "AXLink", "AXRow", "AXCell", "AXMenuItem", "AXTabGroup",
        "AXSearchField", "AXComboBox", "AXIncrementor", "AXDisclosureTriangle", "AXSwitch",
        "AXToggle",
    ]

    /// SwiftUI nests anonymous groups many levels deep; lift their children and drop empty leaves.
    static func pruned(_ elements: [AgentElement]) -> [AgentElement] {
        elements.flatMap { element -> [AgentElement] in
            var element = element
            let children = pruned(element.children ?? [])
            element.children = children.isEmpty ? nil : children
            if element.isInformative { return [element] }
            return children
        }
    }

    /// Depth-first, the order a reader scans; the walk stops early once `predicate` matches.
    func first(where predicate: (AgentElement) -> Bool) -> AgentElement? {
        if predicate(self) { return self }
        for child in children ?? [] {
            if let match = child.first(where: predicate) { return match }
        }
        return nil
    }

    /// The identifier `selectionFrame` gives each selectable palette row.
    static let rowIdentifier = "onecast.row"

    /// Rendered rows in reading order; a lazy list leaves off-screen rows out.
    static func rows(in elements: [AgentElement]) -> [AgentSnapshot.Row] {
        var rows: [AgentSnapshot.Row] = []
        func visit(_ element: AgentElement) {
            guard element.identifier == rowIdentifier else {
                (element.children ?? []).forEach(visit)
                return
            }
            rows.append(
                AgentSnapshot.Row(
                    index: rows.count, label: element.descendantTexts.joined(separator: " · "),
                    selected: element.selected == true, frame: element.frame))
        }
        elements.forEach(visit)
        return rows
    }

    /// The identifier `BarButton` gives each header and footer pill.
    static let barIdentifier = "onecast.bar"

    static func barControls(in elements: [AgentElement]) -> [String] {
        elements.flatMap { element -> [String] in
            guard element.identifier == barIdentifier else {
                return barControls(in: element.children ?? [])
            }
            return [element.label ?? element.descendantTexts.joined(separator: " ")]
        }
    }

    /// The text a row shows, in order, without the row's own identifier.
    private var descendantTexts: [String] {
        let own = [label, title, value].compactMap(\.self)
        return own + (children ?? []).flatMap { child in
            child.identifier == Self.rowIdentifier ? [] : child.descendantTexts
        }
    }

    /// What this node shows; never `identifier`, which names a node rather than drawing text.
    var texts: [String] { [label, title, value].compactMap(\.self) }

    func contains(text: String) -> Bool {
        first { node in node.texts.contains { $0.localizedCaseInsensitiveContains(text) } } != nil
    }
}
