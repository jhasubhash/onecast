import Foundation

/// How far through the current day, week, month or year a moment is.
enum TimeProgress: String, CaseIterable, Sendable {
    case day, week, month, year

    struct Measure: Equatable, Sendable {
        /// 0...1 through the period.
        let fraction: Double
        let remaining: TimeInterval

        /// Floored, so a period never reads 100% until it has actually ended.
        var percent: Int { min(100, Int((fraction * 100).rounded(.down))) }
    }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    private var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// Measured against the real span of the period, so a 23-hour DST day still fills to 100%.
    func measure(at date: Date, calendar: Calendar) -> Measure {
        guard let span = calendar.dateInterval(of: component, for: date), span.duration > 0 else {
            return Measure(fraction: 0, remaining: 0)
        }
        let elapsed = date.timeIntervalSince(span.start)
        let fraction = min(max(elapsed / span.duration, 0), 1)
        return Measure(fraction: fraction, remaining: max(0, span.end.timeIntervalSince(date)))
    }
}
