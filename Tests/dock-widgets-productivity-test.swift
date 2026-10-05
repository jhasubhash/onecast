import Foundation

@main
@MainActor
struct DockWidgetsProductivityTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// Monday 5 October 2026, 10:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_194_400)

    static func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

    static func event(
        _ id: String, from start: Date, to end: Date, allDay: Bool = false, declined: Bool = false
    ) -> MeetingEvent {
        MeetingEvent(
            id: id, title: id, start: start, end: end, isAllDay: allDay, isDeclined: declined,
            calendarID: "cal", calendarName: "Work", calendarColor: nil, calendarItemID: id,
            link: nil)
    }

    static func reminder(
        _ id: String, due: Date? = nil, hasTime: Bool = true, created: Date? = nil,
        list: String = "Inbox"
    ) -> DockReminder {
        DockReminder(
            id: id, title: id, listTitle: list, due: due, hasTime: hasTime, created: created)
    }

    /// ICU pads times with a narrow no-break space, which no author types.
    static func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    static func main() {
        layoutFallsBackToDate()
        agendaDropsFinishedDeclinedAndUnaskedAllDay()
        agendaOrdersAllDayFirstThenByStart()
        todayKeepsUnderwayAndDropsTomorrow()
        featuredPrefersImminentOverUnderway()
        featuredTakesUnderwayWhenNothingIsImminent()
        featuredTakesLaterTodayOverAllDay()
        featuredFallsToAllDayThenLaterDays()
        featuredIsNilForAnEmptyAgenda()
        startLabelReadsAsAGlance()
        modeFallsBackToList()
        remindersOrderDatedBeforeUndated()
        remindersOrderUndatedByCreation()
        listPreferenceIgnoresCaseAndSpace()
        overdueRespectsTimeOfDay()
        overdueDateOnlyWaitsForTheDayToEnd()
        dueLabelNamesNearDays()
        dueLabelAddsTimeOfDay()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Calendar

    static func layoutFallsBackToDate() {
        expect(DockCalendarPlan.Layout(preference: nil) == .date, "no preference is the date")
        expect(DockCalendarPlan.Layout(preference: "bogus") == .date, "an unknown value is the date")
        expect(
            DockCalendarPlan.Layout(preference: "dateAgenda") == .date,
            "a stale raw value never maps to another layout")
        for layout in DockCalendarPlan.Layout.allCases {
            expect(
                DockCalendarPlan.Layout(preference: layout.rawValue) == layout,
                "\(layout) round-trips through its stored value")
        }
        expect(!DockCalendarPlan.Layout.nextEvent.showsDate, "next event alone leaves the date out")
        expect(!DockCalendarPlan.Layout.date.needsEvents, "the date alone reads no events")
    }

    static func agendaDropsFinishedDeclinedAndUnaskedAllDay() {
        let events = [
            event("over", from: at(-120), to: at(-60)),
            event("declined", from: at(30), to: at(60), declined: true),
            event("allDay", from: at(-600), to: at(800), allDay: true),
            event("kept", from: at(30), to: at(60)),
        ]
        let without = DockCalendarPlan.agenda(from: events, now: now, includeAllDay: false)
        expect(without.map(\.id) == ["kept"], "finished, declined and all-day events drop out")
        let with = DockCalendarPlan.agenda(from: events, now: now, includeAllDay: true)
        expect(with.map(\.id) == ["allDay", "kept"], "all-day events return when asked for")
    }

    static func agendaOrdersAllDayFirstThenByStart() {
        let midnight = calendar.startOfDay(for: now)
        let events = [
            event("late", from: at(240), to: at(300)),
            event("early", from: at(30), to: at(60)),
            event("allDay", from: midnight, to: midnight.addingTimeInterval(86_399), allDay: true),
            event("timedAtMidnight", from: midnight, to: at(30)),
        ]
        let agenda = DockCalendarPlan.agenda(from: events, now: now, includeAllDay: true)
        expect(
            agenda.map(\.id) == ["allDay", "timedAtMidnight", "early", "late"],
            "start order, all-day ahead of a timed event beginning at the same moment")
    }

    static func todayKeepsUnderwayAndDropsTomorrow() {
        let events = [
            event("underway", from: at(-30), to: at(30)),
            event("tonight", from: at(600), to: at(660)),
            event("tomorrow", from: at(24 * 60 + 30), to: at(24 * 60 + 90)),
        ]
        let today = DockCalendarPlan.today(events, now: now, calendar: calendar)
        expect(today.map(\.id) == ["underway", "tonight"], "today is what is left of it")
    }

    static func featuredPrefersImminentOverUnderway() {
        let agenda = [
            event("underway", from: at(-30), to: at(30)),
            event("soon", from: at(20), to: at(50)),
            event("later", from: at(120), to: at(150)),
        ]
        let picked = DockCalendarPlan.featured(from: agenda, now: now, calendar: calendar)
        expect(picked?.id == "soon", "a meeting starting within 30 minutes wins over one underway")
    }

    static func featuredTakesUnderwayWhenNothingIsImminent() {
        let agenda = [
            event("underway", from: at(-30), to: at(30)),
            event("later", from: at(31), to: at(60)),
        ]
        let picked = DockCalendarPlan.featured(from: agenda, now: now, calendar: calendar)
        expect(picked?.id == "underway", "31 minutes out is not imminent, so the one underway wins")
    }

    static func featuredTakesLaterTodayOverAllDay() {
        let midnight = calendar.startOfDay(for: now)
        let agenda = [
            event("allDay", from: midnight, to: midnight.addingTimeInterval(86_399), allDay: true),
            event("later", from: at(180), to: at(210)),
        ]
        let picked = DockCalendarPlan.featured(from: agenda, now: now, calendar: calendar)
        expect(picked?.id == "later", "a timed meeting still to come beats an all-day event")
    }

    static func featuredFallsToAllDayThenLaterDays() {
        let midnight = calendar.startOfDay(for: now)
        let allDay = event(
            "allDay", from: midnight, to: midnight.addingTimeInterval(86_399), allDay: true)
        let tomorrow = event("tomorrow", from: at(24 * 60 + 30), to: at(24 * 60 + 90))
        expect(
            DockCalendarPlan.featured(from: [allDay, tomorrow], now: now, calendar: calendar)?.id
                == "allDay",
            "with nothing timed left today, today's all-day event is shown")
        expect(
            DockCalendarPlan.featured(from: [tomorrow], now: now, calendar: calendar)?.id
                == "tomorrow",
            "with nothing today at all, the next day's first event is shown")
    }

    static func featuredIsNilForAnEmptyAgenda() {
        expect(
            DockCalendarPlan.featured(from: [], now: now, calendar: calendar) == nil,
            "nothing to show is nil, not a placeholder")
    }

    static func startLabelReadsAsAGlance() {
        func label(_ event: MeetingEvent) -> String {
            plain(DockCalendarPlan.startLabel(for: event, now: now, calendar: calendar)) ?? ""
        }
        expect(label(event("a", from: at(-5), to: at(25))) == "Now", "an event under way is Now")
        expect(
            label(event("b", from: at(12), to: at(40))) == "in 12 min", "within the hour counts down")
        expect(label(event("c", from: at(210), to: at(240))) == "1:30 PM", "later today is a clock time")
        expect(
            label(event("d", from: at(24 * 60 + 30), to: at(24 * 60 + 60))) == "Tomorrow, 10:30 AM",
            "tomorrow is named")
        expect(
            label(event("e", from: at(3 * 24 * 60), to: at(3 * 24 * 60 + 60))) == "Thu, Oct 8, 10:00 AM",
            "a further day carries its date")
        let midnight = calendar.startOfDay(for: now)
        expect(
            label(event("f", from: midnight, to: midnight.addingTimeInterval(86_399), allDay: true))
                == "All day",
            "an all-day event has no time")
    }

    // MARK: - Reminders

    static func modeFallsBackToList() {
        expect(DockReminderPlan.Mode(preference: nil) == .list, "no preference is the list")
        expect(DockReminderPlan.Mode(preference: "nope") == .list, "an unknown value is the list")
        for mode in DockReminderPlan.Mode.allCases {
            expect(
                DockReminderPlan.Mode(preference: mode.rawValue) == mode,
                "\(mode) round-trips through its stored value")
        }
    }

    static func remindersOrderDatedBeforeUndated() {
        let reminders = [
            reminder("undated"),
            reminder("later", due: at(300)),
            reminder("overdue", due: at(-300)),
            reminder("soon", due: at(30)),
        ]
        expect(
            DockReminderPlan.ordered(reminders).map(\.id) == ["overdue", "soon", "later", "undated"],
            "dated reminders by due date, then the undated")
    }

    static func remindersOrderUndatedByCreation() {
        let reminders = [
            reminder("b", created: at(-10)),
            reminder("a", created: at(-20)),
            reminder("noDate"),
        ]
        expect(
            DockReminderPlan.ordered(reminders).map(\.id) == ["a", "b", "noDate"],
            "undated reminders in the order they were made, unknown creation last")
    }

    static func listPreferenceIgnoresCaseAndSpace() {
        expect(
            DockReminderPlan.includes(listTitle: "Groceries", named: nil), "no preference is every list")
        expect(
            DockReminderPlan.includes(listTitle: "Groceries", named: "  "),
            "a blank preference is every list")
        expect(
            DockReminderPlan.includes(listTitle: "Groceries", named: " groceries "),
            "case and edge spaces do not matter")
        expect(
            !DockReminderPlan.includes(listTitle: "Groceries", named: "Grocery"),
            "a different name is a different list")
    }

    static func overdueRespectsTimeOfDay() {
        let timed = reminder("timed", due: at(-1))
        expect(
            DockReminderPlan.isOverdue(timed, now: now, calendar: calendar),
            "a timed reminder is overdue the minute it passes")
        expect(
            !DockReminderPlan.isOverdue(reminder("future", due: at(1)), now: now, calendar: calendar),
            "a timed reminder in the future is not overdue")
        expect(
            !DockReminderPlan.isOverdue(reminder("none"), now: now, calendar: calendar),
            "no due date is never overdue")
    }

    static func overdueDateOnlyWaitsForTheDayToEnd() {
        let midnight = calendar.startOfDay(for: now)
        let today = reminder("today", due: midnight, hasTime: false)
        let yesterday = reminder("yesterday", due: midnight.addingTimeInterval(-86_400), hasTime: false)
        expect(
            !DockReminderPlan.isOverdue(today, now: now, calendar: calendar),
            "a date-only reminder due today is not overdue today")
        expect(
            DockReminderPlan.isOverdue(yesterday, now: now, calendar: calendar),
            "a date-only reminder from yesterday is overdue")
        expect(
            DockReminderPlan.overdueCount([today, yesterday], now: now, calendar: calendar) == 1,
            "the count agrees with the predicate")
    }

    static func dueLabelNamesNearDays() {
        let midnight = calendar.startOfDay(for: now)
        func label(_ days: Double) -> String? {
            plain(
                DockReminderPlan.dueLabel(
                    for: reminder("r", due: midnight.addingTimeInterval(days * 86_400), hasTime: false),
                    now: now, calendar: calendar))
        }
        expect(label(0) == "Today", "today is named")
        expect(label(1) == "Tomorrow", "tomorrow is named")
        expect(label(-1) == "Yesterday", "yesterday is named")
        expect(label(7) == "Mon, Oct 12", "a further day carries its weekday and date")
        expect(
            DockReminderPlan.dueLabel(for: reminder("r"), now: now, calendar: calendar) == nil,
            "an undated reminder has no label")
    }

    static func dueLabelAddsTimeOfDay() {
        let label = plain(
            DockReminderPlan.dueLabel(
                for: reminder("r", due: at(330)), now: now, calendar: calendar))
        expect(label == "Today, 3:30 PM", "a timed reminder appends its time, got \(label ?? "nil")")
    }
}
