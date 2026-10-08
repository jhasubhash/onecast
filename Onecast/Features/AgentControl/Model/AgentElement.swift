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

    /// Every searchable string on this node, for text-presence checks.
    var texts: [String] { [identifier, label, title, value].compactMap(\.self) }

    func contains(text: String) -> Bool {
        first { node in node.texts.contains { $0.localizedCaseInsensitiveContains(text) } } != nil
    }
}
