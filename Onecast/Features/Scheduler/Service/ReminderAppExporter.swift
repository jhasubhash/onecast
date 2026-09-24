import AppKit
import EventKit

/// Hands a parsed reminder to the app a phrase named; that app reminds, so Onecast schedules none.
@MainActor
enum ReminderAppExporter {

    static func isInstalled(_ app: ReminderApp) -> Bool {
        switch app {
        case .appleReminders: true
        case .things: thingsProbe.flatMap(NSWorkspace.shared.urlForApplication(toOpen:)) != nil
        }
    }

    /// The reminder's first due date, so the caller can confirm when it will go off.
    static func add(
        _ reminder: ParsedReminder, to app: ReminderApp, now: Date, calendar: Calendar
    ) async throws(ReminderAppFailure) -> Date {
        if let refusal = app.refusal(of: reminder.rule) { throw ReminderAppFailure(message: refusal) }
        guard let due = ReminderApp.firstFire(of: reminder.rule, now: now, calendar: calendar) else {
            throw ReminderAppFailure(message: "That time has already passed.")
        }
        switch app {
        case .appleReminders: try await addToReminders(reminder, due: due, calendar: calendar)
        case .things: try await addToThings(reminder.title, due: due, calendar: calendar)
        }
        return due
    }

    private static let thingsProbe = URL(string: "things:///show")

    private static func addToThings(_ title: String, due: Date, calendar: Calendar) async throws(ReminderAppFailure) {
        guard isInstalled(.things) else { throw ReminderAppFailure(message: "Things isn't installed on this Mac.") }
        guard let url = ThingsURL.add(title: title, at: due, calendar: calendar) else {
            throw ReminderAppFailure(message: "Couldn't build the Things link for that reminder.")
        }
        // In the background: the reader asked for a reminder, not to be switched into Things.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            try await NSWorkspace.shared.open(url, configuration: configuration)
        } catch {
            throw ReminderAppFailure(message: "Things didn't take the reminder: \(error.localizedDescription)")
        }
    }

    private static func addToReminders(
        _ parsed: ParsedReminder, due: Date, calendar: Calendar
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
        reminder.title = parsed.title
        reminder.calendar = list
        reminder.dueDateComponents = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: due)
        reminder.addAlarm(EKAlarm(absoluteDate: due))
        if let recurrence = recurrence(for: parsed.rule) { reminder.addRecurrenceRule(recurrence) }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw ReminderAppFailure(message: "Apple Reminders didn't save it: \(error.localizedDescription)")
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
            let days = weekdays.sorted().compactMap(EKWeekday.init(rawValue:)).map(EKRecurrenceDayOfWeek.init)
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
