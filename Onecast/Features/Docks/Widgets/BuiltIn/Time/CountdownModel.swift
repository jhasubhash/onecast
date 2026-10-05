import OnecastPluginKit
import SwiftUI

/// Resolves the typed target once, so "in 3 days" stays one instant across renders and relaunches.
@MainActor
final class CountdownModel {
    private static let resolutionKey = "resolved"
    /// Inside this many seconds of the target the tile counts seconds, not minutes.
    private static let secondsWindow: TimeInterval = 120

    private var resolution: TimeCountdown.Resolution?
    private var isLoaded = false
    private var lease: TimeTickLease?

    init() {
        lease = TimeTickLease(needsSeconds: { [weak self] in self?.isNearTarget ?? false })
    }

    private var isNearTarget: Bool {
        guard let target = resolution?.date else { return false }
        let remaining = target.timeIntervalSinceNow
        return remaining > -1 && remaining <= Self.secondsWindow
    }

    /// The date the target names, nil when empty or unreadable; new text is parsed and saved here.
    func target(_ preferences: DockWidgetPreferences, now: Date) -> Date? {
        if !isLoaded {
            isLoaded = true
            resolution = TimeSnapshot.decode(
                preferences.string(Self.resolutionKey), as: TimeCountdown.Resolution.self)
        }
        let resolved = TimeCountdown.resolve(
            text: preferences.string("target") ?? "", previous: resolution, now: now,
            calendar: .autoupdatingCurrent)
        if resolved != resolution {
            resolution = resolved
            preferences.set(TimeSnapshot.encode(resolved), for: Self.resolutionKey)
            lease?.reevaluate()
        }
        return resolved?.date
    }

    func release() {
        lease?.release()
        lease = nil
    }
}
