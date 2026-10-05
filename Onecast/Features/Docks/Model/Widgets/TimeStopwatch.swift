import Foundation

/// Stopwatch accounting. A running watch is a start date, so it keeps counting across a relaunch.
struct StopwatchState: Codable, Equatable, Sendable {
    struct Lap: Codable, Equatable, Sendable, Identifiable {
        let number: Int
        /// The stopwatch reading when the lap was taken.
        let total: TimeInterval
        /// The time since the previous lap, or since the start for lap 1.
        let split: TimeInterval

        var id: Int { number }
    }

    static let lapLimit = 99

    /// Time banked from earlier runs.
    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date?
    private(set) var laps: [Lap] = []

    var isRunning: Bool { startedAt != nil }
    var isPristine: Bool { !isRunning && accumulated == 0 && laps.isEmpty }

    /// Never negative, so a clock set backwards cannot show a negative reading.
    func elapsed(now: Date) -> TimeInterval {
        let running = startedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, accumulated + max(0, running))
    }

    /// The reading of the lap in progress, i.e. since the last lap.
    func currentSplit(now: Date) -> TimeInterval {
        max(0, elapsed(now: now) - (laps.last?.total ?? 0))
    }

    /// The quickest and slowest splits, once there are two different ones to compare.
    var fastestAndSlowest: (fastest: Int, slowest: Int)? {
        guard laps.count >= 2,
            let fastest = laps.min(by: { $0.split < $1.split }),
            let slowest = laps.max(by: { $0.split < $1.split }),
            fastest.split != slowest.split
        else { return nil }
        return (fastest.number, slowest.number)
    }

    mutating func start(now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    mutating func stop(now: Date) {
        guard startedAt != nil else { return }
        accumulated = elapsed(now: now)
        startedAt = nil
    }

    /// Only a running watch takes laps; the limit keeps the saved state small.
    mutating func lap(now: Date) {
        guard isRunning, laps.count < Self.lapLimit else { return }
        let previous = laps.last?.total ?? 0
        let total = max(elapsed(now: now), previous)
        laps.append(Lap(number: laps.count + 1, total: total, split: total - previous))
    }

    mutating func reset() {
        self = StopwatchState()
    }
}
