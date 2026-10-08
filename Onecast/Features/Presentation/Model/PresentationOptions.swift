import Foundation

/// How the presented window is sized on its display.
enum PresentationWindowSize: String, CaseIterable, Identifiable, Sendable {
    /// Centred with a margin on every side, so the Dock and the desktop edge stay in view.
    case margin
    /// The whole usable area: everything but the menu bar, the Dock and Onecast's docks.
    case fill
    /// macOS full screen, in its own Space.
    case fullScreen
    case unchanged

    var id: Self { self }

    var title: String {
        switch self {
        case .margin: "Centered with a margin"
        case .fill: "Fill the screen"
        case .fullScreen: "Full screen"
        case .unchanged: "Leave as it is"
        }
    }

    /// The one-word name a dock tile has room for.
    var shortTitle: String {
        switch self {
        case .margin: "Margin"
        case .fill: "Fill"
        case .fullScreen: "Full"
        case .unchanged: "As is"
        }
    }
}

/// What happens to every other app's windows while presenting.
enum PresentationOtherApps: String, CaseIterable, Identifiable, Sendable {
    case hide
    case minimize
    case leave

    var id: Self { self }

    var title: String {
        switch self {
        case .hide: "Hide them"
        case .minimize: "Minimize their windows"
        case .leave: "Leave them"
        }
    }
}

/// How far putting other apps away reaches, asked once for displays and once for Spaces.
enum PresentationReach: String, CaseIterable, Identifiable, Sendable {
    /// The display being presented, or the Space it shows now.
    case active
    case all

    var id: Self { self }
}

/// What happens when another app comes to the front while presenting.
enum PresentationAppSwitch: String, CaseIterable, Identifiable, Sendable {
    /// The new app is presented and the previous one is put away.
    case replace
    /// The new app is presented on top; the previous one stays where it is.
    case stack
    case ignore

    var id: Self { self }

    var title: String {
        switch self {
        case .replace: "Present it and put the previous app away"
        case .stack: "Present it on top of the previous app"
        case .ignore: "Leave it alone"
        }
    }
}

/// The margin around a `.margin` window, in percent of the display on each side.
enum PresentationMargin {
    static let range: ClosedRange<Int> = 0...30
    static let defaultPercent = 10
    static let choices = [5, 10, 15, 20, 25]

    static func clamped(_ percent: Int) -> Int {
        min(max(percent, range.lowerBound), range.upperBound)
    }
}
