import Foundation

enum PomodoroPhase: String, Codable, Sendable {
    case focus, shortBreak, longBreak
}

/// What the user configured, clamped so no preference can produce a zero-length or absurd phase.
struct PomodoroSettings: Equatable, Sendable {
    static let focusMinutes: ClosedRange<Int> = 1...180
    static let breakMinutes: ClosedRange<Int> = 1...60
    static let roundLimit: ClosedRange<Int> = 1...12

    let focus: TimeInterval
    let shortBreak: TimeInterval
    let longBreak: TimeInterval
    let rounds: Int
    let autoStart: Bool

    init(focusMinutes: Int?, shortBreakMinutes: Int?, longBreakMinutes: Int?, rounds: Int?, autoStart: Bool) {
        focus = Self.seconds(focusMinutes, fallback: 25, in: Self.focusMinutes)
        shortBreak = Self.seconds(shortBreakMinutes, fallback: 5, in: Self.breakMinutes)
        longBreak = Self.seconds(longBreakMinutes, fallback: 15, in: Self.breakMinutes)
        self.rounds = min(max(rounds ?? 4, Self.roundLimit.lowerBound), Self.roundLimit.upperBound)
        self.autoStart = autoStart
    }

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }

    private static func seconds(_ minutes: Int?, fallback: Int, in range: ClosedRange<Int>) -> TimeInterval {
        TimeInterval(min(max(minutes ?? fallback, range.lowerBound), range.upperBound) * 60)
    }
}

/// A phase that just ended, for the notification the widget posts.
struct PomodoroTransition: Equatable, Sendable {
    let completed: PomodoroPhase
    let next: PomodoroPhase
    let endedAt: Date
    /// How long after `endedAt` the widget noticed; large after a sleep or a relaunch.
    let lateness: TimeInterval
    /// Whether the next phase is already running.
    let startedNext: Bool
}

/// The Pomodoro phase machine. Running state is an end date, so it survives a relaunch unchanged.
struct PomodoroState: Codable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case ready, running, paused
    }

    /// A phase that ended longer ago than this is not worth a notification.
    static let notificationGrace: TimeInterval = 300

    private(set) var phase: PomodoroPhase = .focus
    /// The focus round within the cycle, from 1.
    private(set) var round = 1
    /// Set while running.
    private(set) var endsAt: Date?
    /// Set while paused; with neither set the phase is ready and takes its full duration.
    private(set) var pausedRemaining: TimeInterval?

    var status: Status {
        if endsAt != nil { return .running }
        return pausedRemaining != nil ? .paused : .ready
    }

    func remaining(now: Date, settings: PomodoroSettings) -> TimeInterval {
        let full = settings.duration(of: phase)
        if let endsAt { return min(max(0, endsAt.timeIntervalSince(now)), full) }
        return min(pausedRemaining ?? full, full)
    }

    /// 0 at the start of the phase, 1 at its end.
    func progress(now: Date, settings: PomodoroSettings) -> Double {
        let full = settings.duration(of: phase)
        return 1 - remaining(now: now, settings: settings) / full
    }

    mutating func start(now: Date, settings: PomodoroSettings) {
        guard endsAt == nil else { return }
        endsAt = now.addingTimeInterval(remaining(now: now, settings: settings))
        pausedRemaining = nil
    }

    mutating func pause(now: Date, settings: PomodoroSettings) {
        guard endsAt != nil else { return }
        pausedRemaining = remaining(now: now, settings: settings)
        endsAt = nil
    }

    mutating func reset() {
        self = PomodoroState()
    }

    /// Moves on without completing: a running phase starts its successor at once.
    mutating func skip(now: Date, settings: PomodoroSettings) {
        let wasRunning = endsAt != nil
        moveToNextPhase(rounds: settings.rounds)
        endsAt = wasRunning ? now.addingTimeInterval(settings.duration(of: phase)) : nil
        pausedRemaining = nil
    }

    /// Completes a running phase past its end; auto-start chains the next from the old end date.
    mutating func advance(now: Date, settings: PomodoroSettings) -> PomodoroTransition? {
        guard let end = endsAt, now >= end else { return nil }
        let completed = phase
        moveToNextPhase(rounds: settings.rounds)
        let nextEnd = end.addingTimeInterval(settings.duration(of: phase))
        let chains = settings.autoStart && now < nextEnd
        endsAt = chains ? nextEnd : nil
        pausedRemaining = nil
        return PomodoroTransition(
            completed: completed, next: phase, endedAt: end, lateness: now.timeIntervalSince(end),
            startedNext: chains)
    }

    private mutating func moveToNextPhase(rounds: Int) {
        switch phase {
        case .focus:
            phase = round >= rounds ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .focus
            round += 1
        case .longBreak:
            phase = .focus
            round = 1
        }
    }
}
