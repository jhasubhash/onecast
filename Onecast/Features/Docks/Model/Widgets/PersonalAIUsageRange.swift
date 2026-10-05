import Foundation

/// The window of calendar days an AI Activity tile adds up, always ending with today.
enum PersonalAIUsageRange: String, Sendable, CaseIterable {
    case today
    case last7Days
    case last30Days
    case monthToDate

    static let standard = PersonalAIUsageRange.last7Days

    var title: String {
        switch self {
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .monthToDate: "Month to date"
        }
    }

    /// The word a tile prints under a total, short enough for a compact tile.
    var shortTitle: String {
        switch self {
        case .today: "today"
        case .last7Days: "7 days"
        case .last30Days: "30 days"
        case .monthToDate: "this month"
        }
    }

    /// From the first day's midnight up to tomorrow's, so today is counted whole.
    func interval(now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let tomorrow =
            calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let start: Date
        switch self {
        case .today:
            start = today
        case .last7Days:
            start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .last30Days:
            start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .monthToDate:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? today
        }
        return DateInterval(start: min(start, today), end: tomorrow)
    }

    /// Each local day's midnight, oldest first; the last is today.
    func dayStarts(now: Date, calendar: Calendar) -> [Date] {
        let window = interval(now: now, calendar: calendar)
        var starts: [Date] = []
        var day = window.start
        while day < window.end, starts.count < Self.dayLimit {
            starts.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return starts
    }

    private static let dayLimit = 62
}

/// When a live tile looks again: on a steady beat, and sooner when midnight turns "today" over.
enum PersonalAIUsageSchedule {
    static let refreshSeconds: TimeInterval = 300

    static func delay(now: Date, calendar: Calendar) -> TimeInterval {
        let midnight = PersonalAIUsageRange.today.interval(now: now, calendar: calendar).end
        return min(refreshSeconds, max(midnight.timeIntervalSince(now) + 1, 1))
    }

    /// Whether data fetched at `last` is due again; never fetched is always due.
    static func isStale(since last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= refreshSeconds
    }
}
