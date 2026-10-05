import Foundation

struct PersonalAIUsageDay: Sendable, Equatable, Identifiable {
    let start: Date
    var tokens: PersonalAIUsageTokens

    var id: Date { start }
}

/// One day per calendar day in a range, oldest first; the last is today. Empty days stay in.
struct PersonalAIUsageSeries: Sendable, Equatable {
    let days: [PersonalAIUsageDay]

    var total: PersonalAIUsageTokens { days.reduce(.zero) { $0 + $1.tokens } }
    var today: PersonalAIUsageTokens { days.last?.tokens ?? .zero }
    var busiestDayTotal: Int { days.map(\.tokens.total).max() ?? 0 }
    var hasActivity: Bool { total.total > 0 }

    /// Today's tokens as a share of the busiest day in the range; 0 when nothing happened.
    var todayShare: Double {
        let busiest = busiestDayTotal
        guard busiest > 0 else { return 0 }
        return min(max(Double(today.total) / Double(busiest), 0), 1)
    }
}

struct PersonalAIUsageSummary: Sendable, Equatable, Identifiable {
    let provider: PersonalAIUsageProvider
    let series: PersonalAIUsageSeries

    var id: String { provider.id }
}

enum PersonalAIUsageAggregator {
    /// Buckets entries into the range's local days. An entry outside the window is dropped.
    static func series(
        entries: [PersonalAIUsageEntry], range: PersonalAIUsageRange, now: Date, calendar: Calendar
    ) -> PersonalAIUsageSeries {
        let starts = range.dayStarts(now: now, calendar: calendar)
        let limit = range.interval(now: now, calendar: calendar).end.timeIntervalSince1970
        let boundaries = starts.map(\.timeIntervalSince1970)
        var tokens = [PersonalAIUsageTokens](repeating: .zero, count: starts.count)
        for entry in entries {
            guard let first = boundaries.first, entry.time >= first, entry.time < limit,
                let index = dayIndex(of: entry.time, in: boundaries)
            else { continue }
            tokens[index] += entry.tokens
        }
        return PersonalAIUsageSeries(
            days: zip(starts, tokens).map { PersonalAIUsageDay(start: $0, tokens: $1) })
    }

    /// The last day that starts at or before `time`; boundaries are sorted ascending.
    private static func dayIndex(of time: TimeInterval, in boundaries: [TimeInterval]) -> Int? {
        var low = 0
        var high = boundaries.count
        while low < high {
            let middle = (low + high) / 2
            if boundaries[middle] <= time { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? low - 1 : nil
    }
}
