import Foundation

enum PersonalAIUsageMeasure: String, Sendable, CaseIterable {
    case remaining
    case used

    static let standard = PersonalAIUsageMeasure.remaining

    var title: String {
        switch self {
        case .remaining: "Remaining"
        case .used: "Used"
        }
    }

    /// The word after a percentage: "72% left", "28% used".
    var suffix: String {
        switch self {
        case .remaining: "left"
        case .used: "used"
        }
    }
}

/// One rate-limit window as Codex reports it, with the maths a tile needs on top.
struct PersonalAIUsageLimitWindow: Sendable, Equatable {
    let usedPercent: Int
    let durationMinutes: Int?
    let resetsAt: Date?

    /// Held to 0...100, since the service reports whatever the server sent.
    var used: Int { min(max(usedPercent, 0), 100) }
    var remaining: Int { 100 - used }

    func percent(_ measure: PersonalAIUsageMeasure) -> Int {
        measure == .remaining ? remaining : used
    }

    func fraction(_ measure: PersonalAIUsageMeasure) -> Double {
        Double(percent(measure)) / 100
    }

    /// "72% left" or "28% used".
    func caption(_ measure: PersonalAIUsageMeasure) -> String {
        "\(percent(measure))% \(measure.suffix)"
    }

    /// "5-hour", "Weekly"; `fallback` names a window whose length the server left out.
    func title(fallback: String) -> String {
        durationMinutes.map(PersonalAIUsageLimitLabel.title(minutes:)) ?? fallback
    }

    func shortTitle(fallback: String) -> String {
        durationMinutes.map(PersonalAIUsageLimitLabel.shortTitle(minutes:)) ?? fallback
    }
}

enum PersonalAIUsageLimitLabel {
    private static let minutesPerHour = 60
    private static let minutesPerDay = 1_440
    private static let minutesPerWeek = 10_080

    static func title(minutes: Int) -> String {
        switch minutes {
        case ...0: return "Limit"
        case minutesPerDay: return "Daily"
        case minutesPerWeek: return "Weekly"
        case let m where m % minutesPerDay == 0: return "\(m / minutesPerDay)-day"
        case let m where m % minutesPerHour == 0: return "\(m / minutesPerHour)-hour"
        default: return "\(minutes)-minute"
        }
    }

    /// The same window in a few characters, for a compact tile's caption.
    static func shortTitle(minutes: Int) -> String {
        switch minutes {
        case ...0: return "Limit"
        case minutesPerWeek: return "Week"
        case let m where m % minutesPerDay == 0: return "\(m / minutesPerDay)d"
        case let m where m % minutesPerHour == 0: return "\(m / minutesPerHour)h"
        default: return "\(minutes)m"
        }
    }
}

enum PersonalAIUsageReset {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3_600
    private static let secondsPerDay = 86_400

    /// The words after "resets": a countdown within a day, a weekday within a week, else a date.
    static func phrase(_ date: Date, now: Date, calendar: Calendar) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded(.down))
        if seconds <= 0 { return "now" }
        if seconds < secondsPerMinute { return "in under a minute" }
        if seconds < secondsPerHour { return "in \(seconds / secondsPerMinute)m" }
        if seconds < secondsPerDay {
            let hours = seconds / secondsPerHour
            let minutes = seconds % secondsPerHour / secondsPerMinute
            return minutes == 0 ? "in \(hours)h" : "in \(hours)h \(minutes)m"
        }
        let weekday = calendar.component(.weekday, from: date)
        if seconds < 7 * secondsPerDay {
            return calendar.shortWeekdaySymbols[weekday - 1]
        }
        let month = calendar.component(.month, from: date)
        return "\(calendar.shortMonthSymbols[month - 1]) \(calendar.component(.day, from: date))"
    }
}
