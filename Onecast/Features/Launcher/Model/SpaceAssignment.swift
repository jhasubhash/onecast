import Foundation

/// Which desktops an app's windows open on: the Dock's Options ▸ Assign To.
enum SpaceAssignment: Equatable, Sendable {
    case allDesktops
    /// Zero-based, in the window server's display order — the order the Dock numbers them in.
    case display(Int)
    case none

    /// `com.apple.spaces` stores a binding under the lowercased bundle ID.
    static let allSpacesValue = "AllSpaces"

    /// Every choice the Dock offers for this many displays, in its menu order.
    static func choices(displayCount: Int) -> [SpaceAssignment] {
        [.allDesktops] + (0..<max(displayCount, 1)).map(SpaceAssignment.display) + [.none]
    }

    /// One display has no number to tell it apart, so the Dock calls it "This Desktop".
    func title(displayCount: Int) -> String {
        switch self {
        case .allDesktops: "All Desktops"
        case .display(let index): displayCount > 1 ? "Desktop on Display \(index + 1)" : "This Desktop"
        case .none: "None"
        }
    }

    /// Reads a stored binding against each display's space UUIDs; the main display's are empty.
    static func resolve(binding: String?, displaySpaces: [[String]]) -> SpaceAssignment {
        guard let binding else { return .none }
        if binding == allSpacesValue { return .allDesktops }
        guard let index = displaySpaces.firstIndex(where: { $0.contains(binding) }) else {
            return .none
        }
        return .display(index)
    }

    /// The value to store, given each display's current space UUID; nil removes the binding.
    func bindingValue(currentSpaces: [String]) -> String? {
        switch self {
        case .allDesktops: Self.allSpacesValue
        case .display(let index): currentSpaces.indices.contains(index) ? currentSpaces[index] : nil
        case .none: nil
        }
    }
}
