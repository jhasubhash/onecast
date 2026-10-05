import Foundation

/// Which events the Calendar dock widget lists, and which one its tile features.
enum DockCalendarPlan {
    /// A meeting this close to starting outranks one that is already under way.
    static let imminentWindow: TimeInterval = 30 * 60

    /// What a Calendar tile draws; the raw value is what the widget's preference stores.
    enum Layout: String, CaseIterable, Sendable {
        case date
        case nextEvent
        case dateAndNextEvent
        case dateAndAgenda

        var title: String {
            switch self {
            case .date: "Date"
            case .nextEvent: "Next event"
            case .dateAndNextEvent: "Date + next event"
            case .dateAndAgenda: "Date + agenda"
            }
        }

        var showsDate: Bool { self != .nextEvent }

        var needsEvents: Bool { self != .date }

        /// An unset or unknown preference reads as the plain date.
        init(preference: String?) {
            self = preference.flatMap(Self.init(rawValue:)) ?? .date
        }
    }

    /// Not declined, not over, in start order; an all-day event only when the tile asks for them.
    static func agenda(from events: [MeetingEvent], now: Date, includeAllDay: Bool) -> [MeetingEvent] {
        events
            .filter { !$0.isDeclined && $0.end > now && (includeAllDay || !$0.isAllDay) }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return $0.id < $1.id
            }
    }

    /// Today's events still to come or under way, which is what a day agenda lists.
    static func today(_ agenda: [MeetingEvent], now: Date, calendar: Calendar) -> [MeetingEvent] {
        agenda.filter { $0.start <= now || calendar.isDate($0.start, inSameDayAs: now) }
    }

    /// The one event a tile features: imminent, else under way, else later today, else all-day.
    static func featured(from agenda: [MeetingEvent], now: Date, calendar: Calendar) -> MeetingEvent? {
        let timed = agenda.filter { !$0.isAllDay }
        let imminent = timed.first {
            $0.start > now && $0.start.timeIntervalSince(now) <= imminentWindow
        }
        if let imminent { return imminent }
        if let underway = timed.first(where: { $0.isInProgress(now: now) }) { return underway }
        if let later = timed.first(where: {
            $0.start > now && calendar.isDate($0.start, inSameDayAs: now)
        }) {
            return later
        }
        if let allDay = agenda.first(where: { $0.isAllDay && $0.isInProgress(now: now) }) {
            return allDay
        }
        return agenda.first
    }

    /// When an event happens, in a tile's own few words: "Now", "in 12 min", "3:30 PM".
    static func startLabel(for event: MeetingEvent, now: Date, calendar: Calendar) -> String {
        if event.isAllDay { return "All day" }
        if event.isInProgress(now: now) { return "Now" }
        let delta = event.start.timeIntervalSince(now)
        if delta > 0, delta <= 60 * 60 { return UpcomingWindow.countdown(to: event.start, now: now) }
        let clock = event.start.formatted(calendar.formatStyle.hour().minute())
        let offset = dayOffset(of: event.start, from: now, calendar: calendar)
        switch offset {
        case 0: return clock
        case 1: return "Tomorrow, \(clock)"
        default: return "\(UpcomingWindow.dayLabel(event.start, calendar: calendar)), \(clock)"
        }
    }

    private static func dayOffset(of date: Date, from now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: day).day ?? 0
    }
}
