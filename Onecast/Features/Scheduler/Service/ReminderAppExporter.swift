import AppKit
import EventKit

/// Hands a reminder to an app a phrase named; that app does its own reminding.
@MainActor
enum ReminderAppExporter {
    static func isInstalled(_ app: ReminderApp) -> Bool {
        switch app {
        case .appleReminders: true
        case .things: thingsProbe.flatMap(NSWorkspace.shared.urlForApplication(toOpen:)) != nil
        }
    }

    /// The first due date, nil for a to-do kept without a time; the caller confirms either.
    static func add(
        title: String, rule: ScheduleRule?, to app: ReminderApp, now: Date, calendar: Calendar
    ) async throws(ReminderAppFailure) -> Date? {
        var due: Date?
        if let rule {
            if let refusal = app.refusal(of: rule) { throw ReminderAppFailure(message: refusal) }
            due = ReminderApp.firstFire(of: rule, now: now, calendar: calendar)
            if due == nil { throw ReminderAppFailure(message: "That time has already passed.") }
        }
        switch app {
        case .appleReminders:
            try await addToReminders(title, rule: rule, due: due, calendar: calendar)
        case .things:
            try await addToThings(title, due: due, calendar: calendar)
        }
        return due
    }

    private static let thingsProbe = URL(string: "things:///show")

    private static func addToThings(
        _ title: String, due: Date?, calendar: Calendar
    ) async throws(ReminderAppFailure) {
        guard isInstalled(.things) else {
            throw ReminderAppFailure(message: "Things isn't installed on this Mac.")
        }
        guard let url = ThingsURL.add(title: title, at: due, calendar: calendar) else {
            throw ReminderAppFailure(message: "Couldn't build the Things link for that reminder.")
        }
        // In the background: the reader asked for a reminder, not to be switched into Things.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            try await NSWorkspace.shared.open(url, configuration: configuration)
        } catch {
            throw ReminderAppFailure(
                message: "Things didn't take the reminder: \(error.localizedDescription)")
        }
    }

    private static func addToReminders(
        _ title: String, rule: ScheduleRule?, due: Date?, calendar: Calendar
    ) async throws(ReminderAppFailure) {
        if Permissions.remindersAccess() == .notDetermined {
            _ = await Permissions.requestRemindersAccess()
        }
        guard Permissions.remindersAccess() == .granted else {
            throw ReminderAppFailure(
                message: "Onecast can't reach Apple Reminders. Allow it in System Settings → Privacy "
                    + "& Security → Reminders.")
        }
        let store = EKEventStore()
        guard let list = store.defaultCalendarForNewReminders() else {
            throw ReminderAppFailure(message: "Apple Reminders has no default list to add to.")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        if let recurrence = rule.flatMap(recurrence(for:)) { reminder.addRecurrenceRule(recurrence) }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw ReminderAppFailure(
                message: "Apple Reminders didn't save it: \(error.localizedDescription)")
        }
    }

    /// Only the shapes `ReminderApp.refusal` lets through reach here, so an interval never does.
    private static func recurrence(for rule: ScheduleRule) -> EKRecurrenceRule? {
        switch rule {
        case .once, .interval:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly(let weekdays, _, _):
            let days = weekdays.sorted().compactMap(EKWeekday.init(rawValue:))
                .map(EKRecurrenceDayOfWeek.init)
            return EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil,
                end: nil)
        case .monthly(let day, _, _):
            return EKRecurrenceRule(
                recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil,
                daysOfTheMonth: [NSNumber(value: day)], monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }
}
