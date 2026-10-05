import Foundation

/// Every string the time widgets show, so the tiles and popovers never format a time themselves.
enum TimeFormat {
    /// `25:00`, `1:02:03`. Remaining time rounds up so a timer reads `00:01` until it is done.
    static func duration(
        _ interval: TimeInterval, rounding: FloatingPointRoundingRule = .down
    ) -> String {
        let total = wholeSeconds(interval, rounding: rounding)
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    /// A stopwatch reading with `fractionDigits` (0...2) digits of a second after the point.
    static func stopwatch(_ interval: TimeInterval, fractionDigits: Int) -> String {
        let value = interval.isFinite ? min(max(0, interval), 1e9) : 0
        let digits = min(max(fractionDigits, 0), 2)
        let scale = digits == 2 ? 100.0 : 10.0
        let whole = duration(value)
        guard digits > 0 else { return whole }
        let fraction = Int((value - value.rounded(.down)) * scale)
        return whole + "." + String(format: "%0\(digits)d", fraction)
    }

    /// `jmm` lets the system's 12/24-hour switch pick the shape, so it never disagrees with it.
    static func clock(_ date: Date, calendar: Calendar, zone: TimeZone, showSeconds: Bool) -> String {
        CalcDateFormatters.string(
            from: date, calendar: calendar, zone: zone, template: showSeconds ? "jmmss" : "jmm")
    }

    /// The clock as digits and day-period words (`7:42`, `PM`), so a tile can give the digits room.
    static func clockParts(
        _ date: Date, calendar: Calendar, zone: TimeZone, showSeconds: Bool
    ) -> (time: String, period: String) {
        let words = clock(date, calendar: calendar, zone: zone, showSeconds: showSeconds)
            .split(separator: " ")
        let time = words.filter { $0.contains(where: \.isNumber) }
        let period = words.filter { !$0.contains(where: \.isNumber) }
        return (time.joined(separator: " "), period.joined(separator: " "))
    }

    static func weekday(_ date: Date, calendar: Calendar) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: calendar.timeZone, template: "EEE")
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: calendar.timeZone, template: "d")
    }

    /// `Oct 6`, or `6 Oct` where the locale says so.
    static func monthDay(_ date: Date, calendar: Calendar) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: calendar.timeZone, template: "MMMd")
    }

    /// `Tue, Oct 6`, or the spelled-out `Tuesday, October 6`.
    static func date(_ date: Date, calendar: Calendar, long: Bool) -> String {
        CalcDateFormatters.string(
            from: date, calendar: calendar, zone: calendar.timeZone,
            template: long ? "EEEEMMMMd" : "EEEMMMd")
    }

    /// `Dec 25, 2026 9:00 AM`: a target date with the year, since a countdown can be far away.
    static func dateTime(_ date: Date, calendar: Calendar) -> String {
        CalcDateFormatters.string(
            from: date, calendar: calendar, zone: calendar.timeZone, template: "yMMMdjmm")
    }

    static func weekNumber(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    /// The day of the year, counting from 1.
    static func dayOfYear(_ date: Date, calendar: Calendar) -> Int {
        calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    /// `Today`, `Tomorrow`, `Yesterday`, else `+2d` / `−2d`.
    static func dayOffset(_ days: Int) -> String {
        switch days {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: days > 0 ? "+\(days)d" : "\u{2212}\(-days)d"
        }
    }

    /// `+5h`, `−3h`, `+5:30`, or `±0h` for the same clock.
    static func hourOffset(_ seconds: Int) -> String {
        guard seconds != 0 else { return "\u{00B1}0h" }
        let sign = seconds > 0 ? "+" : "\u{2212}"
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(sign)\(hours)h" : "\(sign)\(hours):" + String(format: "%02d", rest)
    }

    /// Capped far above any shown duration, since `Int(.infinity)` traps.
    private static func wholeSeconds(
        _ interval: TimeInterval, rounding: FloatingPointRoundingRule
    ) -> Int {
        guard interval.isFinite else { return 0 }
        return Int(min(max(0, interval), 1e9).rounded(rounding))
    }
}
