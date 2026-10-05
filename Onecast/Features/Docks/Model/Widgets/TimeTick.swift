import Foundation

/// Clock-face maths for the time widgets: when a tick lands and where the analog hands point.
enum TimeTick {
    /// The next whole multiple of `step` seconds after `date`, so a minute tick lands on :00.
    static func nextBoundary(after date: Date, step: TimeInterval) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / step).rounded(.down) * step + step)
    }

    /// Whole minutes since the reference date; two instants share one iff they share a minute.
    static func minuteIndex(_ date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
    }

    /// Hand angles in degrees, clockwise from 12 o'clock.
    struct Angles: Equatable, Sendable {
        let hour: Double
        let minute: Double
        let second: Double
    }

    /// The minute hand creeps with the seconds and the hour hand with the minutes, as on a clock.
    static func angles(at date: Date, calendar: Calendar) -> Angles {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double(parts.second ?? 0)
        let minutes = Double(parts.minute ?? 0) + seconds / 60
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
        return Angles(hour: hours / 12 * 360, minute: minutes / 60 * 360, second: seconds / 60 * 360)
    }
}
