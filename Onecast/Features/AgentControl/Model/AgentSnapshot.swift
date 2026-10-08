import Foundation

/// What `state` answers: the app as data, so a driver reasons over facts instead of pixels.
struct AgentSnapshot: Codable, Equatable, Sendable {
    /// Points, top-left origin on the primary display: what `screencapture -R` takes.
    struct Rect: Codable, Equatable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Build: Codable, Equatable, Sendable {
        let bundleID: String
        let version: String
        let pid: Int32
        /// Without the grant SwiftUI never builds its tree, and `elements` stays near-empty.
        let accessibilityTrusted: Bool
    }

    struct Frame: Codable, Equatable, Sendable {
        let mode: String
        let query: String
        let selection: Int
    }

    struct Palette: Codable, Equatable, Sendable {
        let visible: Bool
        let mode: String
        let query: String
        let selection: Int
        let backStack: [Frame]
        let aiBar: Bool
        let collapsed: Bool
        let editingField: Bool
        let controlListOpen: Bool
        let frame: Rect?
        var rows: [Row]?
        /// The header and footer pills, as labelled: "Run Command, ↵".
        var barControls: [String]?
    }

    /// One rendered palette row; `index` is its place among rendered rows, not `selection`.
    struct Row: Codable, Equatable, Sendable {
        let index: Int
        let label: String
        let selected: Bool
        let frame: Rect?
    }

    struct Window: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let className: String
        let level: Int
        let isKey: Bool
        let isVisible: Bool
        let frame: Rect
        var elements: [AgentElement]?
    }

    struct Focus: Codable, Equatable, Sendable {
        let keyWindow: String?
        let firstResponder: String?
        let frontmostApp: String?
    }

    /// What `capture` wrote. `cacheDisplay` means no Screen Recording grant: glass won't match.
    struct Capture: Codable, Equatable, Sendable {
        let path: String
        let window: String
        let frame: Rect
        let pixelWidth: Int
        let pixelHeight: Int
        let method: String
        var rows: [Row]?
    }

    let build: Build
    var palette: Palette
    var windows: [Window]
    let focus: Focus
}
