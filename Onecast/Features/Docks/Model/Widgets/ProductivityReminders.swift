import Foundation

/// One incomplete reminder, flattened out of EventKit so nothing EventKit-shaped reaches a view.
struct DockReminder: Identifiable, Hashable, Sendable {
    /// EventKit's `calendarItemIdentifier`, the handle that finds it again to complete it.
    let id: String
    let title: String
    let listTitle: String
    let due: Date?
    /// A reminder due on a day with no time of day is overdue only once the day has passed.
    let hasTime: Bool
    let created: Date?
}

/// Ordering, filtering and wording for the Reminders dock widget. Every clock read is injected.
enum DockReminderPlan {
    /// What a Reminders tile draws; the raw value is what the widget's preference stores.
    enum Mode: String, CaseIterable, Sendable {
        case list
        case next
        case count

        var title: String {
            switch self {
            case .list: "List"
            case .next: "Next reminder"
            case .count: "Count"
            }
        }

        /// An unset or unknown preference reads as the list.
        init(preference: String?) {
            self = preference.flatMap(Self.init(rawValue:)) ?? .list
        }
    }

    /// Dated reminders first, soonest due first; undated ones follow in the order they were made.
    static func ordered(_ reminders: [DockReminder]) -> [DockReminder] {
        reminders.sorted { lhs, rhs in
            switch (lhs.due, rhs.due) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                if lhs.created != rhs.created {
                    return (lhs.created ?? .distantFuture) < (rhs.created ?? .distantFuture)
                }
                let byTitle = lhs.title.localizedStandardCompare(rhs.title)
                return byTitle == .orderedSame ? lhs.id < rhs.id : byTitle == .orderedAscending
            }
        }
    }

    /// Whether a list passes the widget's list-name preference; empty means every list.
    static func includes(listTitle: String, named preference: String?) -> Bool {
        guard let wanted = normalized(preference) else { return true }
        return normalized(listTitle) == wanted
    }

    /// The preference as typed, trimmed; nil when it is blank.
    static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed.lowercased()
    }

    static func isOverdue(_ reminder: DockReminder, now: Date, calendar: Calendar) -> Bool {
        guard let due = reminder.due else { return false }
        if reminder.hasTime { return due < now }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    static func overdueCount(_ reminders: [DockReminder], now: Date, calendar: Calendar) -> Int {
        reminders.filter { isOverdue($0, now: now, calendar: calendar) }.count
    }

    /// "Today, 3:30 PM", "Tomorrow", "Mon, Oct 12, 9:00 AM"; nil for a reminder with no due date.
    static func dueLabel(for reminder: DockReminder, now: Date, calendar: Calendar) -> String? {
        guard let due = reminder.due else { return nil }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let dayLabel: String
        switch offset {
        case 0: dayLabel = "Today"
        case 1: dayLabel = "Tomorrow"
        case -1: dayLabel = "Yesterday"
        default:
            dayLabel = due.formatted(calendar.formatStyle.weekday(.abbreviated).month(.abbreviated).day())
        }
        guard reminder.hasTime else { return dayLabel }
        return "\(dayLabel), \(due.formatted(calendar.formatStyle.hour().minute()))"
    }
}
