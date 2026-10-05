import OnecastPluginKit
import SwiftUI

/// A stopwatch's live state and saved copy; a running watch is a start date, so it outlives a quit.
@MainActor
@Observable
final class StopwatchModel {
    private static let stateKey = "state"

    private(set) var state = StopwatchState()

    @ObservationIgnored private var preferences: DockWidgetPreferences?
    @ObservationIgnored private var lease: TimeTickLease?

    init() {
        lease = TimeTickLease(needsSeconds: { [weak self] in self?.state.isRunning ?? false })
    }

    /// The preferences arrive with the first context, so that is when the saved watch is read.
    func bind(_ preferences: DockWidgetPreferences) {
        guard self.preferences?.instanceID != preferences.instanceID else { return }
        self.preferences = preferences
        state =
            TimeSnapshot.decode(preferences.string(Self.stateKey), as: StopwatchState.self)
            ?? StopwatchState()
        lease?.reevaluate()
    }

    func toggle() {
        update { state in
            if state.isRunning {
                state.stop(now: Date())
            } else {
                state.start(now: Date())
            }
        }
    }

    func lap() {
        update { $0.lap(now: Date()) }
    }

    func reset() {
        update { $0.reset() }
    }

    func release() {
        lease?.release()
        lease = nil
    }

    private func update(_ change: (inout StopwatchState) -> Void) {
        guard let preferences else { return }
        var next = state
        change(&next)
        state = next
        preferences.set(TimeSnapshot.encode(next), for: Self.stateKey)
        lease?.reevaluate()
    }
}
