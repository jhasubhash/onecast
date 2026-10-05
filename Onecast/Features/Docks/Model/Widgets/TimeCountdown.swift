import Foundation

/// Countdown maths: what is left until a target, and turning a typed target into a date.
enum TimeCountdown {
    struct Breakdown: Equatable, Sendable {
        let days: Int
        let hours: Int
        let minutes: Int
        let seconds: Int
        /// Whether the target has passed, in which case the parts say how long ago.
        let isPast: Bool

        var isUnderMinute: Bool { days == 0 && hours == 0 && minutes == 0 }

        /// The two largest units that matter: `12d 5h`, `5h 23m`, `23m`, `45s`.
        var summary: String {
            if days > 0 { return "\(days)d \(hours)h" }
            if hours > 0 { return "\(hours)h \(minutes)m" }
            if minutes > 0 { return "\(minutes)m" }
            return "\(seconds)s"
        }

        /// Every unit down to the second from the largest that matters: `12d 5h 23m`, `5h 23m 45s`.
        var detail: String {
            if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
            if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
            return "\(minutes)m \(seconds)s"
        }
    }

    /// A typed target and its instant, kept so "in 3 days" does not slide forward on each read.
    struct Resolution: Codable, Equatable, Sendable {
        let text: String
        let date: Date
    }

    /// Calendar-aware, so a spring-forward day still counts as one day.
    static func breakdown(from now: Date, to target: Date, calendar: Calendar) -> Breakdown {
        let isPast = target <= now
        let (start, end) = isPast ? (target, now) : (now, target)
        let parts = calendar.dateComponents([.day, .hour, .minute, .second], from: start, to: end)
        return Breakdown(
            days: parts.day ?? 0, hours: parts.hour ?? 0, minutes: parts.minute ?? 0,
            seconds: parts.second ?? 0, isPast: isPast)
    }

    /// The saved resolution when the text is unchanged, else a fresh parse; nil if unreadable.
    static func resolve(
        text: String, previous: Resolution?, now: Date, calendar: Calendar
    ) -> Resolution? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let previous, previous.text == trimmed { return previous }
        return parse(trimmed, now: now, calendar: calendar).map { Resolution(text: trimmed, date: $0) }
    }

    /// An ISO date, with or without a time or zone, first; else a natural phrase such as `Dec 25`.
    static func parse(_ text: String, now: Date, calendar: Calendar) -> Date? {
        isoDate(text, calendar: calendar)
            ?? NaturalDateParser.date(from: text, now: now, calendar: calendar)
    }

    private static let localFormats = [
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd"
    ]

    /// A date-only value is midnight in the Mac's zone, and a zone-less time is local time.
    private static func isoDate(_ text: String, calendar: Calendar) -> Date? {
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        for format in localFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
