import Foundation

@MainActor
enum HydrationChecks {
    private static let t = DockWidgetsPersonalTests.self

    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let locale = Locale(identifier: "en_US")

    private static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    private static func entry(_ text: String, _ milliliters: Int? = 250) -> HydrationEntry {
        HydrationEntry(id: UUID(), date: date(text), milliliters: milliliters)
    }

    static func run() {
        logKeepsNewestFirst()
        logIgnoresDuplicateAndRemoves()
        revertInvertsEachChange()
        daysGroupByCalendarDay()
        daysSplitAtLocalMidnightNotUTC()
        historyWindowsRecentDays()
        persistenceRoundTrips()
        persistenceSurvivesBadEntries()
        persistenceTreatsGarbageAsEmpty()
        settingsClamp()
        settingsReminderRules()
        progressByUnit()
        reminderDue()
        formatting()
        fileStore()
    }

    // MARK: - Log

    private static func logKeepsNewestFirst() {
        var log = HydrationLog()
        log.add(entry("2025-03-10T08:00:00Z"))
        log.add(entry("2025-03-10T12:00:00Z"))
        log.add(entry("2025-03-10T10:00:00Z"))
        let hours = log.entries.map { calendar.component(.hour, from: $0.date) }
        t.expect(hours == [12, 10, 8], "entries stay newest first however they arrive")
        t.expect(log.lastDrink == date("2025-03-10T12:00:00Z"), "the last drink is the newest entry")
    }

    private static func logIgnoresDuplicateAndRemoves() {
        var log = HydrationLog()
        let drink = entry("2025-03-10T08:00:00Z")
        log.add(drink)
        log.add(drink)
        t.expect(log.entries.count == 1, "adding the same entry twice keeps one")
        t.expect(log.remove(id: drink.id) == drink, "remove hands back what it removed")
        t.expect(log.remove(id: drink.id) == nil, "removing an unknown id is a no-op")
        t.expect(log.lastDrink == nil, "an empty log has no last drink")
    }

    private static func revertInvertsEachChange() {
        var log = HydrationLog()
        let first = entry("2025-03-10T08:00:00Z")
        let second = entry("2025-03-10T09:00:00Z")
        log.add(first)
        log.add(second)
        log.revert(.added(second))
        t.expect(log.entries == [first], "undoing an add removes that drink")
        log.revert(.removed(second))
        t.expect(log.entries == [second, first], "undoing a removal puts the drink back in order")
        log.revert(.removed(second))
        t.expect(log.entries.count == 2, "undoing a removal twice cannot duplicate the drink")
    }

    // MARK: - Days

    private static func daysGroupByCalendarDay() {
        var log = HydrationLog()
        log.add(entry("2025-03-10T08:00:00Z", 250))
        log.add(entry("2025-03-10T18:00:00Z", 500))
        log.add(entry("2025-03-08T09:00:00Z", 300))
        let days = log.days(calendar: calendar)
        t.expect(days.count == 2, "two calendar days with drinks give two rows; the empty one is skipped")
        t.expect(days.first?.milliliters == 750, "a day totals its drinks")
        t.expect(days.first?.entries.first?.milliliters == 500, "a day lists newest first")
        t.expect(days.last?.count == 1, "the older day keeps its own count")
        let today = log.day(containing: date("2025-03-10T23:59:00Z"), calendar: calendar)
        t.expect(today.milliliters == 750, "day(containing:) finds the day from any time in it")
        let empty = log.day(containing: date("2025-03-09T12:00:00Z"), calendar: calendar)
        t.expect(empty.entries.isEmpty && empty.milliliters == 0, "a day without drinks is empty")
    }

    private static func daysSplitAtLocalMidnightNotUTC() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var log = HydrationLog()
        log.add(entry("2025-03-10T14:30:00Z"))
        log.add(entry("2025-03-10T15:30:00Z"))
        let days = log.days(calendar: tokyo)
        t.expect(days.count == 2, "15:30Z is already tomorrow in Tokyo, so the days split at local midnight")
    }

    private static func historyWindowsRecentDays() {
        var log = HydrationLog()
        log.add(entry("2025-03-10T08:00:00Z"))
        log.add(entry("2025-03-09T08:00:00Z"))
        log.add(entry("2025-03-08T08:00:00Z"))
        log.add(entry("2025-03-05T08:00:00Z"))
        let now = date("2025-03-10T20:00:00Z")
        let recent = log.history(now: now, calendar: calendar, recentDays: 3, showingOlder: false)
        t.expect(recent.days.count == 3, "the recent window is today and the two days before it")
        t.expect(recent.hasOlder, "older drinks are flagged so the list can offer them")
        let all = log.history(now: now, calendar: calendar, recentDays: 3, showingOlder: true)
        t.expect(all.days.count == 4 && !all.hasOlder, "showing older lists every day and flags nothing more")
        var fresh = HydrationLog()
        fresh.add(entry("2025-03-10T08:00:00Z"))
        let only = fresh.history(now: now, calendar: calendar, recentDays: 3, showingOlder: false)
        t.expect(!only.hasOlder, "nothing older means no offer")
    }

    // MARK: - Persistence

    private static func persistenceRoundTrips() {
        var log = HydrationLog()
        log.add(entry("2025-03-10T08:00:00Z", 250))
        log.add(entry("2025-03-10T09:00:00Z", nil))
        guard let data = try? log.encoded() else { return t.expect(false, "a log encodes") }
        t.expect(HydrationLog.decode(data) == log, "a log survives encode and decode, nil amounts included")
    }

    private static func persistenceSurvivesBadEntries() {
        let good = entry("2025-03-10T08:00:00Z")
        let goodJSON = #"{"id":"\#(good.id.uuidString)","date":"2025-03-10T08:00:00Z","milliliters":250}"#
        let json = #"{"entries":[\#(goodJSON),{"id":"nope"},"junk",{"date":"2025-03-10T08:00:00Z"}]}"#
        let log = HydrationLog.decode(Data(json.utf8))
        t.expect(log.entries.map(\.id) == [good.id], "one bad entry loses only itself")
    }

    private static func persistenceTreatsGarbageAsEmpty() {
        t.expect(HydrationLog.decode(Data("not json".utf8)).entries.isEmpty, "garbage decodes to an empty log")
        t.expect(HydrationLog.decode(Data()).entries.isEmpty, "empty data decodes to an empty log")
        t.expect(HydrationLog.decode(Data("[]".utf8)).entries.isEmpty, "a wrong top-level shape decodes to an empty log")
    }

    // MARK: - Settings

    private static func settings(
        reminder: String? = "60", drinkSize: String? = nil, goal: String? = nil, drinks: String? = nil,
        tracks: Bool = true
    ) -> HydrationSettings {
        HydrationSettings(
            reminder: reminder, savesHistory: true, tracksAmounts: tracks, drinkSize: drinkSize,
            goalMilliliters: goal, goalDrinks: drinks)
    }

    private static func settingsClamp() {
        let wild = settings(drinkSize: "999999", goal: "-5", drinks: "0")
        t.expect(wild.drinkMilliliters == 5000, "a huge drink size clamps to the ceiling")
        t.expect(wild.goalMilliliters == 100, "a negative goal clamps to the floor")
        t.expect(wild.goalDrinks == 1, "a zero drink goal clamps to one so progress never divides by zero")
        let garbage = settings(drinkSize: "lots", goal: "", drinks: nil)
        t.expect(garbage.drinkMilliliters == 250, "a drink size that is not a number keeps the default")
        t.expect(garbage.goalMilliliters == 2000, "an empty goal keeps the default")
        t.expect(garbage.goalDrinks == 8, "a missing drink goal keeps the default")
        t.expect(settings(drinkSize: " 330 ").drinkMilliliters == 330, "surrounding spaces are ignored")
    }

    private static func settingsReminderRules() {
        t.expect(settings(reminder: nil).reminderMinutes == nil, "an empty reminder field turns reminders off")
        t.expect(settings(reminder: "0").reminderMinutes == nil, "zero turns reminders off")
        t.expect(settings(reminder: "-10").reminderMinutes == nil, "a negative interval turns reminders off")
        t.expect(settings(reminder: "soon").reminderMinutes == 60, "text that is not a number keeps the default")
        t.expect(settings(reminder: "45").reminderMinutes == 45, "a valid interval is kept")
        t.expect(settings(reminder: "99999").reminderMinutes == 1440, "an interval over a day clamps to a day")
        t.expect(HydrationSettings.standard.reminderMinutes == 60, "the standard instance reminds hourly")
    }

    private static func progressByUnit() {
        var log = HydrationLog()
        log.add(entry("2025-03-10T08:00:00Z", 500))
        log.add(entry("2025-03-10T09:00:00Z", 750))
        let day = log.day(containing: date("2025-03-10T12:00:00Z"), calendar: calendar)
        let measured = settings(goal: "2500").progress(for: day)
        t.expect(measured.consumed == 1250 && measured.goal == 2500, "measured progress counts millilitres")
        t.expect(measured.percent == 50 && measured.fraction == 0.5, "half the goal is 50 percent")
        let counted = settings(drinks: "4", tracks: false).progress(for: day)
        t.expect(counted.consumed == 2 && counted.goal == 4, "counted progress counts drinks")
        let over = settings(goal: "1000").progress(for: day)
        t.expect(over.isReached && over.percent == 125, "past the goal reads over 100 percent")
        t.expect(over.ringFraction == 1, "the ring stops at full")
    }

    // MARK: - Reminder

    private static func reminderDue() {
        let start = date("2025-03-10T08:00:00Z")
        let drink = date("2025-03-10T09:00:00Z")
        let nudge = date("2025-03-10T10:00:00Z")
        let none = HydrationReminder.due(lastDrink: nil, watchStart: start, lastReminder: nil, minutes: 60)
        t.expect(none == date("2025-03-10T09:00:00Z"), "with no drink the clock counts from when watching began")
        let afterDrink = HydrationReminder.due(
            lastDrink: drink, watchStart: start, lastReminder: nil, minutes: 30)
        t.expect(afterDrink == date("2025-03-10T09:30:00Z"), "a drink restarts the clock")
        let stale = HydrationReminder.due(
            lastDrink: date("2025-03-09T09:00:00Z"), watchStart: start, lastReminder: nil, minutes: 60)
        t.expect(stale == date("2025-03-10T09:00:00Z"), "yesterday's drink never makes a relaunch fire at once")
        let afterNudge = HydrationReminder.due(
            lastDrink: drink, watchStart: start, lastReminder: nudge, minutes: 60)
        t.expect(afterNudge == date("2025-03-10T11:00:00Z"), "an ignored nudge waits a full interval")
        t.expect(
            HydrationReminder.due(lastDrink: drink, watchStart: start, lastReminder: nil, minutes: nil) == nil,
            "reminders off means no due time")
        t.expect(
            HydrationReminder.secondsUntil(start, now: drink) == 0, "a due time already past is zero seconds away")
        t.expect(HydrationReminder.secondsUntil(drink, now: start) == 3600, "an hour ahead is 3600 seconds")
    }

    // MARK: - Formatting

    private static func formatting() {
        t.expect(HydrationFormat.milliliters(1250, locale: locale) == "1,250 mL", "millilitres are grouped")
        t.expect(HydrationFormat.drinks(1, locale: locale) == "1 drink", "one drink is singular")
        t.expect(HydrationFormat.drinks(5, locale: locale) == "5 drinks", "several drinks are plural")
        let measured = HydrationProgress(consumed: 1250, goal: 2000, unit: .milliliters)
        t.expect(HydrationFormat.progress(measured, locale: locale) == "1,250 / 2,000 mL", "measured progress reads consumed over goal")
        t.expect(HydrationFormat.goalLine(measured, locale: locale) == "of 2,000 mL", "the goal line states the goal")
        let counted = HydrationProgress(consumed: 5, goal: 8, unit: .drinks)
        t.expect(HydrationFormat.progress(counted, locale: locale) == "5 / 8 drinks", "counted progress reads in drinks")
        t.expect(HydrationFormat.countdown(seconds: 0) == "<1m", "a due-now countdown reads under a minute")
        t.expect(HydrationFormat.countdown(seconds: 59) == "1m", "59 seconds rounds up to a minute")
        t.expect(HydrationFormat.countdown(seconds: 42 * 60) == "42m", "minutes read plainly")
        t.expect(HydrationFormat.countdown(seconds: 65 * 60) == "1h 05m", "an hour and five minutes pads the minutes")
        t.expect(HydrationFormat.countdown(seconds: 120 * 60) == "2h", "whole hours drop the minutes")
        let now = date("2025-03-10T20:00:00Z")
        t.expect(
            HydrationFormat.dayTitle(date("2025-03-10T00:00:00Z"), now: now, calendar: calendar, locale: locale) == "Today",
            "today is named")
        t.expect(
            HydrationFormat.dayTitle(date("2025-03-09T00:00:00Z"), now: now, calendar: calendar, locale: locale) == "Yesterday",
            "yesterday is named")
        let older = HydrationFormat.dayTitle(
            date("2025-03-05T00:00:00Z"), now: now, calendar: calendar, locale: locale)
        t.expect(older.contains("Mar") && older.contains("5"), "older days carry their date")
        let time = HydrationFormat.time(date("2025-03-10T09:10:00Z"), calendar: calendar, locale: locale)
        t.expect(time.contains("9:10"), "a drink time reads hours and minutes")
        t.expect(
            HydrationFormat.phrase(entry("2025-03-10T09:10:00Z", nil), locale: locale) == "a drink",
            "an unmeasured drink reads as a drink in a sentence")
        t.expect(
            HydrationFormat.reminderBody(measured, locale: locale) == "Today so far: 1,250 / 2,000 mL.",
            "the reminder states how far today is")
        let done = HydrationProgress(consumed: 2000, goal: 2000, unit: .milliliters)
        t.expect(
            HydrationFormat.reminderBody(done, locale: locale).hasPrefix("Goal reached"),
            "a reached goal says so")
    }

    // MARK: - File

    private static func fileStore() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "hydration-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = HydrationHistoryFile(directory: directory, instanceID: "ABC-123")
        t.expect(file.load().entries.isEmpty, "a missing file loads as an empty log")
        var log = HydrationLog()
        log.add(entry("2025-03-10T08:00:00Z"))
        do {
            try file.save(log)
        } catch {
            return t.expect(false, "saving creates the directory and writes: \(error)")
        }
        t.expect(file.load() == log, "a saved log loads back identical")
        t.expect(file.url.lastPathComponent == "ABC-123.json", "the file is named for the instance id")
        let hostile = HydrationHistoryFile(directory: directory, instanceID: "../../etc/x")
        t.expect(hostile.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
                 "an id can never step out of the history directory")
        file.delete()
        t.expect(file.load().entries.isEmpty, "a deleted file loads as an empty log")
        file.delete()
    }
}
