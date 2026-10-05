import Foundation

/// When the next "drink water" nudge is due.
enum HydrationReminder {
    /// Latest of last drink, watch start and last nudge, plus the interval: no nag on relaunch.
    static func due(
        lastDrink: Date?, watchStart: Date, lastReminder: Date?, minutes: Int?
    ) -> Date? {
        guard let minutes else { return nil }
        let anchor = max(lastDrink ?? .distantPast, watchStart, lastReminder ?? .distantPast)
        return anchor.addingTimeInterval(TimeInterval(minutes) * 60)
    }

    static func secondsUntil(_ due: Date, now: Date) -> TimeInterval {
        max(0, due.timeIntervalSince(now))
    }
}
