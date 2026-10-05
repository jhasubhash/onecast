import OnecastPluginKit
import SwiftUI

/// A Pomodoro timer's live state: the phase machine, its saved copy, and the end-of-phase alert.
@MainActor
@Observable
final class FocusTimerModel {
    private static let stateKey = "state"

    private(set) var state = PomodoroState()

    @ObservationIgnored private var preferences: DockWidgetPreferences?
    @ObservationIgnored private var lease: TimeTickLease?
    @ObservationIgnored private let player = TimeAlertPlayer()

    init() {
        lease = TimeTickLease(
            needsSeconds: { [weak self] in self?.state.status == .running },
            onTick: { [weak self] date in self?.tick(date) })
    }

    static func settings(_ preferences: DockWidgetPreferences) -> PomodoroSettings {
        PomodoroSettings(
            focusMinutes: preferences.integer("focusMinutes"),
            shortBreakMinutes: preferences.integer("shortBreakMinutes"),
            longBreakMinutes: preferences.integer("longBreakMinutes"),
            rounds: preferences.integer("rounds"), autoStart: preferences.bool("autoStart"))
    }

    /// The preferences arrive with the first context, so that is when the saved timer is read.
    func bind(_ preferences: DockWidgetPreferences) {
        guard self.preferences?.instanceID != preferences.instanceID else { return }
        self.preferences = preferences
        state =
            TimeSnapshot.decode(preferences.string(Self.stateKey), as: PomodoroState.self)
            ?? PomodoroState()
        lease?.reevaluate()
    }

    func toggle() {
        update { state, settings in
            if state.status == .running {
                state.pause(now: Date(), settings: settings)
            } else {
                state.start(now: Date(), settings: settings)
            }
        }
    }

    func reset() {
        update { state, _ in state.reset() }
    }

    func skip() {
        update { state, settings in state.skip(now: Date(), settings: settings) }
    }

    func release() {
        lease?.release()
        lease = nil
        player.stop()
    }

    private func update(_ change: (inout PomodoroState, PomodoroSettings) -> Void) {
        guard let preferences else { return }
        var next = state
        change(&next, Self.settings(preferences))
        commit(next)
    }

    private func commit(_ next: PomodoroState) {
        state = next
        preferences?.set(TimeSnapshot.encode(next), for: Self.stateKey)
        lease?.reevaluate()
    }

    private func tick(_ date: Date) {
        guard let preferences else { return }
        let settings = Self.settings(preferences)
        var next = state
        guard let transition = next.advance(now: date, settings: settings) else { return }
        commit(next)
        guard transition.lateness <= PomodoroState.notificationGrace else { return }
        let message = Self.message(for: transition, settings: settings)
        TimeNotificationService.announce(
            title: message.title, body: message.body, tint: transition.next == .focus ? .red : .green)
        if preferences.bool("sound") { player.chime() }
    }

    private static func message(
        for transition: PomodoroTransition, settings: PomodoroSettings
    ) -> (title: String, body: String) {
        let minutes = Int(settings.duration(of: transition.next) / 60)
        switch (transition.completed, transition.next) {
        case (.focus, .longBreak): return ("Focus complete", "Take a \(minutes)-minute long break.")
        case (.focus, _): return ("Focus complete", "Take a \(minutes)-minute break.")
        default: return ("Break over", "Back to focus for \(minutes) minutes.")
        }
    }
}
