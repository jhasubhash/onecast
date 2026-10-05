import Foundation

/// A daily alarm's time of day and when it next rings.
struct TimeAlarm: Equatable, Sendable {
    let hour: Int
    let minute: Int

    /// An alarm that rang longer ago than this is not worth ringing, e.g. after the Mac slept.
    static let lateGrace: TimeInterval = 15 * 60
    /// More fires than a year holds cannot lie inside one grace window.
    private static let skipLimit = 366

    /// `07:00`, `7:30`, `7:30 pm`, `7pm`, `19:05`; nil for anything else.
    static func parse(_ text: String) -> TimeAlarm? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: " ", with: "")
        var meridiem: String?
        for suffix in ["am", "pm"] where value.hasSuffix(suffix) {
            meridiem = suffix
            value.removeLast(2)
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
            let hour = Int(parts[0]), let minute = parts.count == 2 ? Int(parts[1]) : 0,
            (0...59).contains(minute)
        else { return nil }
        guard let meridiem else {
            return (0...23).contains(hour) ? TimeAlarm(hour: hour, minute: minute) : nil
        }
        guard (1...12).contains(hour) else { return nil }
        return TimeAlarm(hour: hour % 12 + (meridiem == "pm" ? 12 : 0), minute: minute)
    }

    /// The first ring strictly after `date`; a time lost to a DST jump rings at the next valid one.
    func nextFire(after date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(
            after: date, matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    /// The latest ring in `(lastChecked, now]`, if it is recent enough to still be worth ringing.
    func due(since lastChecked: Date, now: Date, calendar: Calendar) -> Date? {
        guard var fire = nextFire(after: lastChecked, calendar: calendar), fire <= now else { return nil }
        for _ in 0..<Self.skipLimit {
            guard let following = nextFire(after: fire, calendar: calendar), following <= now else { break }
            fire = following
        }
        return now.timeIntervalSince(fire) <= Self.lateGrace ? fire : nil
    }

    /// 24-hour `07:00`, the shape the preference is stored in.
    var text: String { String(format: "%02d:%02d", hour, minute) }
}
