import Foundation

/// What hiding the macOS Dock writes, gives back, and whether the Dock must restart for it.
enum NativeDockHidingPlan {
    /// The three `com.apple.dock` keys hiding touches; nil is a key the user never set.
    struct Settings: Codable, Sendable, Hashable {
        var autohide: Bool?
        var autohideDelay: Double?
        var autohideTimeModifier: Double?
    }

    enum Change<Value: Sendable & Hashable>: Sendable, Hashable {
        case set(Value)
        case remove

        init(to target: Value?) {
            self = target.map { .set($0) } ?? .remove
        }
    }

    /// The writes that move the Dock's preferences from one `Settings` to another.
    struct Edits: Sendable, Hashable {
        static let none = Edits(from: Settings(), to: Settings())

        var autohide: Change<Bool>?
        var autohideDelay: Change<Double>?
        var autohideTimeModifier: Change<Double>?

        init(from current: Settings, to target: Settings) {
            if current.autohide != target.autohide { autohide = Change(to: target.autohide) }
            if current.autohideDelay != target.autohideDelay {
                autohideDelay = Change(to: target.autohideDelay)
            }
            if current.autohideTimeModifier != target.autohideTimeModifier {
                autohideTimeModifier = Change(to: target.autohideTimeModifier)
            }
        }

        var isEmpty: Bool {
            autohide == nil && autohideDelay == nil && autohideTimeModifier == nil
        }
    }

    struct Step: Sendable, Hashable {
        /// The user's own values, held until the Dock is given back; nil once it is.
        var originals: Settings?
        var edits: Edits

        var restartsDock: Bool { !edits.isEmpty }
    }

    /// Long enough that the pointer never dwells at the edge for it.
    static let suppressedDelay = 1000.0

    /// `saved` is the sentinel's originals while hiding is on; they pass through untouched.
    static func step(
        hidden: Bool, hiding: NativeDockHiding, current: Settings, saved: Settings?
    ) -> Step {
        guard hidden else {
            guard let saved else { return Step(originals: nil, edits: .none) }
            return Step(originals: nil, edits: Edits(from: current, to: saved))
        }
        let originals = saved ?? current
        let target = hiddenSettings(hiding, originals: originals)
        return Step(originals: originals, edits: Edits(from: current, to: target))
    }

    /// Reachable only autohides; suppressed also pushes the reveal delay out of reach.
    static func hiddenSettings(_ hiding: NativeDockHiding, originals: Settings) -> Settings {
        var target = originals
        target.autohide = true
        if hiding == .suppressed { target.autohideDelay = suppressedDelay }
        return target
    }
}
