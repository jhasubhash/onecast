// Pure maths behind the Docks time widgets: ticks, formats, Pomodoro, stopwatch, countdown, alarm.
import Foundation

@main
@MainActor
struct DockWidgetsTimeTests {
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

    static func main() {
        ticksLandOnTheNextBoundary()
        analogHandsFollowTheTime()
        durationsRoundTheRightWay()
        stopwatchReadingsCarryFractions()
        clocksFollowTheLocaleHourCycle()
        offsetLabelsReadNaturally()
        pomodoroRunsAWholeCycle()
        pomodoroPausesAndResumes()
        pomodoroAutoStartChainsOnlyWhenNotStale()
        pomodoroSkipAndResetAndClamping()
        pomodoroSurvivesARelaunch()
        stopwatchAccountsForRunsAndLaps()
        stopwatchSurvivesARelaunch()
        stopwatchGuardsItsLimits()
        countdownCountsCalendarDays()
        countdownParsesIsoAndNaturalTargets()
        countdownResolutionStaysPut()
        progressUsesTheRealPeriodLength()
        progressFloorsAtTheEdges()
        alarmTimesParse()
        alarmFiresDailyAcrossMidnight()
        alarmHandlesDaylightSaving()
        alarmDueRespectsTheGrace()
        worldClockResolvesNamesAndIdentifiers()
        worldClockOffsetsCrossDates()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Helpers

    static func calendar(
        _ zone: String, locale: String = "en_US", firstWeekday: Int = 1
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: locale)
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// `2026-03-08 12:30:00` read as wall-clock time in `zone`.
    static func at(_ text: String, _ zone: String = "UTC") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = text.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    static let settings = PomodoroSettings(
        focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, rounds: 4, autoStart: false)

    static let chaining = PomodoroSettings(
        focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, rounds: 4, autoStart: true)

    // MARK: - Ticks and formats

    static func ticksLandOnTheNextBoundary() {
        let base = at("2026-10-05 10:00:00")
        let second = TimeTick.nextBoundary(after: base.addingTimeInterval(0.4), step: 1)
        expect(second == base.addingTimeInterval(1), "a second tick lands on the next whole second")
        let minute = TimeTick.nextBoundary(after: base.addingTimeInterval(30), step: 60)
        expect(minute == at("2026-10-05 10:01:00"), "a minute tick lands on :00")
        let exact = TimeTick.nextBoundary(after: base, step: 60)
        expect(exact == at("2026-10-05 10:01:00"), "a tick exactly on a boundary waits for the next")
        expect(
            TimeTick.minuteIndex(base.addingTimeInterval(59)) == TimeTick.minuteIndex(base),
            "instants in one minute share a minute index")
        expect(
            TimeTick.minuteIndex(base.addingTimeInterval(60)) == TimeTick.minuteIndex(base) + 1,
            "the next minute has the next index")
    }

    static func analogHandsFollowTheTime() {
        let utc = calendar("UTC")
        let three = TimeTick.angles(at: at("2026-10-05 03:00:00"), calendar: utc)
        expect(near(three.hour, 90) && near(three.minute, 0) && near(three.second, 0), "3:00 points at 3")
        let half = TimeTick.angles(at: at("2026-10-05 12:30:30"), calendar: utc)
        expect(near(half.hour, 15.25), "the hour hand creeps with the minutes: \(half.hour)")
        expect(near(half.minute, 183), "the minute hand creeps with the seconds: \(half.minute)")
        expect(near(half.second, 180), "30 seconds is half a turn")
        let afternoon = TimeTick.angles(at: at("2026-10-05 15:00:00"), calendar: utc)
        expect(near(afternoon.hour, 90), "the 24-hour clock folds onto the 12-hour face")
        let tokyo = TimeTick.angles(at: at("2026-10-05 00:00:00"), calendar: calendar("Asia/Tokyo"))
        expect(near(tokyo.hour, 270), "hands read the calendar's zone, not UTC")
    }

    static func durationsRoundTheRightWay() {
        expect(TimeFormat.duration(1500) == "25:00", "25 minutes")
        expect(TimeFormat.duration(3723) == "1:02:03", "an hour reads h:mm:ss")
        expect(TimeFormat.duration(59.9) == "00:59", "floors by default")
        expect(TimeFormat.duration(0.2, rounding: .up) == "00:01", "a timer holds 00:01 until done")
        expect(TimeFormat.duration(-5) == "00:00", "never negative")
        expect(TimeFormat.duration(.infinity) == "00:00", "a non-finite value cannot trap")
        expect(TimeFormat.duration(.nan) == "00:00", "NaN cannot trap")
    }

    static func stopwatchReadingsCarryFractions() {
        expect(TimeFormat.stopwatch(75.34, fractionDigits: 1) == "01:15.3", "tenths")
        expect(TimeFormat.stopwatch(75.349, fractionDigits: 2) == "01:15.34", "hundredths")
        expect(TimeFormat.stopwatch(75.9, fractionDigits: 0) == "01:15", "no fraction floors")
        expect(TimeFormat.stopwatch(3601.5, fractionDigits: 1) == "1:00:01.5", "hours with a fraction")
        expect(TimeFormat.stopwatch(-1, fractionDigits: 2) == "00:00.00", "never negative")
        expect(TimeFormat.stopwatch(.infinity, fractionDigits: 1) == "00:00.0", "non-finite is zero")
    }

    static func clocksFollowTheLocaleHourCycle() {
        let moment = at("2026-10-05 21:41:07", "UTC")
        let us = calendar("UTC", locale: "en_US")
        let gb = calendar("UTC", locale: "en_GB")
        expect(
            TimeFormat.clock(moment, calendar: us, zone: us.timeZone, showSeconds: false) == "9:41 PM",
            "12-hour locale: \(TimeFormat.clock(moment, calendar: us, zone: us.timeZone, showSeconds: false))"
        )
        expect(
            TimeFormat.clock(moment, calendar: gb, zone: gb.timeZone, showSeconds: false) == "21:41",
            "24-hour locale")
        expect(
            TimeFormat.clock(moment, calendar: gb, zone: gb.timeZone, showSeconds: true) == "21:41:07",
            "seconds when asked")
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        expect(
            TimeFormat.clock(moment, calendar: gb, zone: tokyo, showSeconds: false) == "06:41",
            "a zone argument shifts the clock")
        expect(TimeFormat.date(moment, calendar: us, long: false) == "Mon, Oct 5", "short date")
        expect(TimeFormat.date(moment, calendar: us, long: true) == "Monday, October 5", "long date")
        let twelve = TimeFormat.clockParts(moment, calendar: us, zone: us.timeZone, showSeconds: true)
        expect(twelve.time == "9:41:07" && twelve.period == "PM", "digits and period split: \(twelve)")
        let twentyFour = TimeFormat.clockParts(moment, calendar: gb, zone: gb.timeZone, showSeconds: false)
        expect(twentyFour.time == "21:41" && twentyFour.period.isEmpty, "a 24-hour clock has no period")
        expect(TimeFormat.monthDay(moment, calendar: us) == "Oct 5", "US month and day")
        expect(TimeFormat.monthDay(moment, calendar: gb) == "5 Oct", "GB day and month")
        expect(TimeFormat.weekNumber(at("2026-01-01", "UTC"), calendar: us) == 1, "Jan 1 is week 1")
    }

    static func offsetLabelsReadNaturally() {
        expect(TimeFormat.hourOffset(0) == "\u{00B1}0h", "same clock")
        expect(TimeFormat.hourOffset(5 * 3600) == "+5h", "whole hours ahead")
        expect(TimeFormat.hourOffset(-3 * 3600) == "\u{2212}3h", "whole hours behind")
        expect(TimeFormat.hourOffset(19800) == "+5:30", "half-hour zones")
        expect(TimeFormat.hourOffset(-12600) == "\u{2212}3:30", "half-hour zones behind")
        expect(TimeFormat.hourOffset(20700) == "+5:45", "quarter-hour zones")
        expect(TimeFormat.dayOffset(0) == "Today", "today")
        expect(TimeFormat.dayOffset(1) == "Tomorrow", "tomorrow")
        expect(TimeFormat.dayOffset(-1) == "Yesterday", "yesterday")
        expect(TimeFormat.dayOffset(2) == "+2d", "two days ahead")
        let utc = calendar("UTC")
        expect(TimeFormat.dayOfYear(at("2026-01-01"), calendar: utc) == 1, "Jan 1 is day 1")
        expect(TimeFormat.dayOfYear(at("2027-12-31"), calendar: utc) == 365, "a common year ends on 365")
        expect(TimeFormat.dayOfYear(at("2028-12-31"), calendar: utc) == 366, "a leap year ends on 366")
    }

    // MARK: - Pomodoro

    static func pomodoroRunsAWholeCycle() {
        var state = PomodoroState()
        var now = at("2026-10-05 09:00:00")
        var order: [PomodoroPhase] = []
        expect(state.status == .ready, "a new timer is ready")
        expect(state.remaining(now: now, settings: settings) == 1500, "ready shows the full focus")
        for _ in 0..<8 {
            state.start(now: now, settings: settings)
            order.append(state.phase)
            now = now.addingTimeInterval(settings.duration(of: state.phase))
            let transition = state.advance(now: now, settings: settings)
            expect(transition?.completed == order.last, "the finished phase is reported")
            expect(transition?.lateness == 0, "an on-time end has no lateness")
            expect(transition?.startedNext == false, "without auto-start the next phase waits")
            expect(state.status == .ready, "the next phase is ready, not running")
        }
        expect(
            order == [
                .focus, .shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak
            ], "four focus rounds then a long break: \(order)")
        expect(state.phase == .focus && state.round == 1, "a long break starts a new cycle")
    }

    static func pomodoroPausesAndResumes() {
        var state = PomodoroState()
        let start = at("2026-10-05 09:00:00")
        state.start(now: start, settings: settings)
        expect(state.status == .running, "started")
        expect(state.advance(now: start.addingTimeInterval(1499), settings: settings) == nil, "not over yet")
        state.pause(now: start.addingTimeInterval(600), settings: settings)
        expect(state.status == .paused, "paused")
        expect(
            state.remaining(now: start.addingTimeInterval(9999), settings: settings) == 900,
            "paused time does not drain")
        expect(
            state.advance(now: start.addingTimeInterval(9999), settings: settings) == nil, "paused never ends"
        )
        let resume = start.addingTimeInterval(7200)
        state.start(now: resume, settings: settings)
        expect(
            state.remaining(now: resume.addingTimeInterval(300), settings: settings) == 600,
            "resume continues from the paused remainder")
        expect(near(state.progress(now: resume.addingTimeInterval(300), settings: settings), 0.6), "progress")
        var idle = PomodoroState()
        idle.pause(now: start, settings: settings)
        expect(idle.status == .ready, "pausing a ready timer does nothing")
    }

    static func pomodoroAutoStartChainsOnlyWhenNotStale() {
        let start = at("2026-10-05 09:00:00")
        var state = PomodoroState()
        state.start(now: start, settings: chaining)
        let end = start.addingTimeInterval(1500)
        let late = state.advance(now: end.addingTimeInterval(2), settings: chaining)
        expect(late?.startedNext == true, "auto-start runs the next phase")
        expect(late.map { near($0.lateness, 2) } == true, "lateness is measured from the end date")
        expect(state.status == .running && state.phase == .shortBreak, "the break is running")
        expect(
            state.remaining(now: end.addingTimeInterval(2), settings: chaining) == 298,
            "the break counts from the old end date, not from when it was noticed")

        var asleep = PomodoroState()
        asleep.start(now: start, settings: chaining)
        let wake = end.addingTimeInterval(3 * 3600)
        let stale = asleep.advance(now: wake, settings: chaining)
        expect(stale?.startedNext == false, "a break that is itself over does not start")
        expect(asleep.status == .ready && asleep.phase == .shortBreak, "it waits ready after a long absence")
        expect((stale?.lateness ?? 0) > PomodoroState.notificationGrace, "a stale end is past the grace")
    }

    static func pomodoroSkipAndResetAndClamping() {
        let start = at("2026-10-05 09:00:00")
        var state = PomodoroState()
        state.skip(now: start, settings: settings)
        expect(state.phase == .shortBreak && state.status == .ready, "skipping a ready phase stays ready")
        state.start(now: start, settings: settings)
        state.skip(now: start.addingTimeInterval(10), settings: settings)
        expect(state.phase == .focus && state.round == 2, "skipping a break begins round 2")
        expect(state.status == .running, "skipping a running phase runs the next")
        expect(
            state.remaining(now: start.addingTimeInterval(10), settings: settings) == 1500,
            "the next phase takes its full duration")
        state.reset()
        expect(state == PomodoroState(), "reset returns to the first focus")

        let wild = PomodoroSettings(
            focusMinutes: 0, shortBreakMinutes: 500, longBreakMinutes: -3, rounds: 99, autoStart: false)
        expect(wild.focus == 60, "focus clamps to 1 minute")
        expect(wild.shortBreak == 3600, "a break clamps to an hour")
        expect(wild.longBreak == 60, "a negative break clamps to a minute")
        expect(wild.rounds == 12, "rounds clamp to 12")
        let blank = PomodoroSettings(
            focusMinutes: nil, shortBreakMinutes: nil, longBreakMinutes: nil, rounds: nil, autoStart: false)
        expect(blank == settings, "missing preferences read as the 25/5/15/4 defaults")

        let single = PomodoroSettings(
            focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, rounds: 1, autoStart: false)
        var solo = PomodoroState()
        solo.skip(now: start, settings: single)
        expect(solo.phase == .longBreak, "one round per cycle goes straight to the long break")
    }

    static func pomodoroSurvivesARelaunch() {
        let start = at("2026-10-05 09:00:00")
        var state = PomodoroState()
        state.start(now: start, settings: settings)
        let saved = TimeSnapshot.encode(state)
        let restored = TimeSnapshot.decode(saved, as: PomodoroState.self)
        expect(restored == state, "a saved timer decodes to itself")
        expect(
            restored?.remaining(now: start.addingTimeInterval(1200), settings: settings) == 300,
            "the end date, not a counter, survives")
        expect(TimeSnapshot.decode("not json", as: PomodoroState.self) == nil, "junk reads as a fresh start")
        expect(TimeSnapshot.decode(nil, as: PomodoroState.self) == nil, "no save reads as a fresh start")
    }

    // MARK: - Stopwatch

    static func stopwatchAccountsForRunsAndLaps() {
        var watch = StopwatchState()
        let start = at("2026-10-05 09:00:00")
        expect(watch.isPristine, "a new watch is pristine")
        watch.lap(now: start)
        expect(watch.laps.isEmpty, "a stopped watch takes no laps")
        watch.start(now: start)
        watch.start(now: start.addingTimeInterval(5))
        expect(watch.elapsed(now: start.addingTimeInterval(10)) == 10, "a second start changes nothing")
        watch.lap(now: start.addingTimeInterval(10))
        watch.lap(now: start.addingTimeInterval(25))
        expect(watch.laps.map(\.split) == [10, 15], "splits are the gaps between laps")
        expect(watch.laps.map(\.total) == [10, 25], "totals are the readings")
        expect(watch.currentSplit(now: start.addingTimeInterval(30)) == 5, "the open lap runs on")
        watch.stop(now: start.addingTimeInterval(40))
        watch.stop(now: start.addingTimeInterval(99))
        expect(watch.elapsed(now: start.addingTimeInterval(99)) == 40, "stopped time does not count")
        watch.start(now: start.addingTimeInterval(100))
        expect(watch.elapsed(now: start.addingTimeInterval(110)) == 50, "a resumed run adds to the bank")
        watch.lap(now: start.addingTimeInterval(110))
        expect(watch.laps.last?.split == 25, "a lap after a pause counts only running time")
        expect(watch.fastestAndSlowest?.fastest == 1 && watch.fastestAndSlowest?.slowest == 3, "extremes")
        watch.reset()
        expect(watch.isPristine && watch.elapsed(now: start) == 0, "reset clears everything")
    }

    static func stopwatchSurvivesARelaunch() {
        var watch = StopwatchState()
        let start = at("2026-10-05 09:00:00")
        watch.start(now: start)
        watch.lap(now: start.addingTimeInterval(60))
        let restored = TimeSnapshot.decode(TimeSnapshot.encode(watch), as: StopwatchState.self)
        expect(restored == watch, "a running watch decodes to itself")
        expect(
            restored?.elapsed(now: start.addingTimeInterval(3600)) == 3600,
            "a running watch keeps counting while the app is closed")
        expect(restored?.laps.count == 1, "laps survive")
    }

    static func stopwatchGuardsItsLimits() {
        var watch = StopwatchState()
        let start = at("2026-10-05 09:00:00")
        watch.start(now: start)
        for step in 1...(StopwatchState.lapLimit + 5) {
            watch.lap(now: start.addingTimeInterval(Double(step)))
        }
        expect(watch.laps.count == StopwatchState.lapLimit, "laps stop at the limit")
        expect(watch.fastestAndSlowest == nil, "equal splits have no extremes")

        var skewed = StopwatchState()
        skewed.start(now: start)
        skewed.lap(now: start.addingTimeInterval(30))
        skewed.lap(now: start.addingTimeInterval(10))
        expect(skewed.laps.last?.split == 0, "a clock set backwards never yields a negative split")
        expect(skewed.elapsed(now: start.addingTimeInterval(-50)) == 0, "nor a negative reading")
    }

    // MARK: - Countdown

    static func countdownCountsCalendarDays() {
        let ny = calendar("America/New_York")
        let springForward = TimeCountdown.breakdown(
            from: at("2026-03-07 12:00:00", "America/New_York"),
            to: at("2026-03-08 12:00:00", "America/New_York"), calendar: ny)
        expect(
            springForward.days == 1 && springForward.hours == 0,
            "a 23-hour DST day is still one day: \(springForward)")
        let fallBack = TimeCountdown.breakdown(
            from: at("2026-10-31 12:00:00", "America/New_York"),
            to: at("2026-11-01 12:00:00", "America/New_York"), calendar: ny)
        expect(fallBack.days == 1 && fallBack.hours == 0, "a 25-hour DST day is still one day")

        let utc = calendar("UTC")
        let monthEnd = TimeCountdown.breakdown(
            from: at("2026-01-31 00:00:00"), to: at("2026-03-01 00:00:00"), calendar: utc)
        expect(monthEnd.days == 29, "Jan 31 to Mar 1 in a common year is 29 days: \(monthEnd.days)")
        let leap = TimeCountdown.breakdown(
            from: at("2028-02-28 00:00:00"), to: at("2028-03-01 00:00:00"), calendar: utc)
        expect(leap.days == 2, "Feb 28 to Mar 1 in a leap year is 2 days")
        let common = TimeCountdown.breakdown(
            from: at("2027-02-28 00:00:00"), to: at("2027-03-01 00:00:00"), calendar: utc)
        expect(common.days == 1, "Feb 28 to Mar 1 in a common year is 1 day")

        let mixed = TimeCountdown.breakdown(
            from: at("2026-10-05 08:00:00"), to: at("2026-10-17 13:23:45"), calendar: utc)
        expect(
            (mixed.days, mixed.hours, mixed.minutes, mixed.seconds) == (12, 5, 23, 45), "d/h/m/s: \(mixed)")
        expect(mixed.summary == "12d 5h" && !mixed.isPast, "summary keeps the two largest units")
        let hours = TimeCountdown.breakdown(
            from: at("2026-10-05 08:00:00"), to: at("2026-10-05 13:23:45"), calendar: utc)
        expect(hours.summary == "5h 23m", "hours and minutes")
        let minutes = TimeCountdown.breakdown(
            from: at("2026-10-05 08:00:00"), to: at("2026-10-05 08:23:45"), calendar: utc)
        expect(minutes.summary == "23m" && !minutes.isUnderMinute, "minutes alone")
        let seconds = TimeCountdown.breakdown(
            from: at("2026-10-05 08:00:00"), to: at("2026-10-05 08:00:45"), calendar: utc)
        expect(seconds.summary == "45s" && seconds.isUnderMinute, "the last minute reads in seconds")
        expect(
            [mixed.detail, hours.detail, minutes.detail, seconds.detail]
                == ["12d 5h 23m", "5h 23m 45s", "23m 45s", "0m 45s"], "detail runs down to the second")

        let past = TimeCountdown.breakdown(
            from: at("2026-10-05 08:00:00"), to: at("2026-10-04 06:00:00"), calendar: utc)
        expect(past.isPast && past.days == 1 && past.hours == 2, "a passed target counts how long ago")
        let now = TimeCountdown.breakdown(
            from: at("2026-10-05 08:00:00"), to: at("2026-10-05 08:00:00"), calendar: utc)
        expect(now.isPast, "reaching the target counts as done")
    }

    static func countdownParsesIsoAndNaturalTargets() {
        let ny = calendar("America/New_York")
        let now = at("2026-10-05 09:00:00", "America/New_York")
        expect(
            TimeCountdown.parse("2026-12-25", now: now, calendar: ny) == at("2026-12-25", "America/New_York"),
            "a date alone is midnight local")
        expect(
            TimeCountdown.parse("2026-12-25 18:30", now: now, calendar: ny)
                == at("2026-12-25 18:30:00", "America/New_York"), "a space-separated time")
        expect(
            TimeCountdown.parse("2026-12-25T18:30", now: now, calendar: ny)
                == at("2026-12-25 18:30:00", "America/New_York"), "a T-separated time")
        expect(
            TimeCountdown.parse("2026-12-25T18:30:15", now: now, calendar: ny)
                == at("2026-12-25 18:30:15", "America/New_York"), "seconds")
        expect(
            TimeCountdown.parse("2026-12-25T18:30:00Z", now: now, calendar: ny)
                == at("2026-12-25 18:30:00", "UTC"), "an explicit zone wins over the Mac's")
        expect(
            TimeCountdown.parse("2026-12-25T18:30:00+09:00", now: now, calendar: ny)
                == at("2026-12-25 09:30:00", "UTC"), "an offset is honoured")
        expect(
            TimeCountdown.parse("in 3 days", now: now, calendar: ny)
                == at("2026-10-08 09:00:00", "America/New_York"),
            "natural phrases fall through to the shared parser")
        expect(TimeCountdown.parse("blorp", now: now, calendar: ny) == nil, "nonsense is unreadable")
        expect(
            TimeCountdown.resolve(text: "   ", previous: nil, now: now, calendar: ny) == nil,
            "blank is nothing")
    }

    static func countdownResolutionStaysPut() {
        let ny = calendar("America/New_York")
        let first = at("2026-10-05 09:00:00", "America/New_York")
        let later = at("2026-10-06 09:00:00", "America/New_York")
        let resolved = TimeCountdown.resolve(text: " in 3 days ", previous: nil, now: first, calendar: ny)
        expect(resolved?.date == at("2026-10-08 09:00:00", "America/New_York"), "parsed once")
        let kept = TimeCountdown.resolve(text: "in 3 days", previous: resolved, now: later, calendar: ny)
        expect(kept == resolved, "the same text keeps its instant instead of sliding")
        let changed = TimeCountdown.resolve(text: "in 4 days", previous: resolved, now: later, calendar: ny)
        expect(changed?.date == at("2026-10-10 09:00:00", "America/New_York"), "new text parses afresh")
        let restored = TimeSnapshot.decode(TimeSnapshot.encode(resolved), as: TimeCountdown.Resolution.self)
        expect(restored == resolved, "a resolution survives a relaunch")
        let unreadable = TimeCountdown.resolve(text: "blorp", previous: resolved, now: later, calendar: ny)
        expect(unreadable == nil, "unreadable text drops the old target")
    }

    // MARK: - Progress

    static func progressUsesTheRealPeriodLength() {
        let utc = calendar("UTC", firstWeekday: 2)
        let noon = at("2026-10-07 12:00:00")
        expect(near(TimeProgress.day.measure(at: noon, calendar: utc).fraction, 0.5), "noon is half a day")
        let week = TimeProgress.week.measure(at: noon, calendar: utc)
        expect(near(week.fraction, 2.5 / 7), "Wednesday noon, Monday-first week: \(week.fraction)")
        let sundayFirst = calendar("UTC", firstWeekday: 1)
        expect(
            near(TimeProgress.week.measure(at: noon, calendar: sundayFirst).fraction, 3.5 / 7),
            "a Sunday-first week reads further along")
        let leap = TimeProgress.month.measure(at: at("2028-02-15 12:00:00"), calendar: utc)
        expect(near(leap.fraction, 14.5 / 29), "February in a leap year has 29 days: \(leap.fraction)")
        let common = TimeProgress.month.measure(at: at("2027-02-15 12:00:00"), calendar: utc)
        expect(near(common.fraction, 14.5 / 28), "February in a common year has 28")
        let leapYear = TimeProgress.year.measure(at: at("2028-07-01 00:00:00"), calendar: utc)
        expect(near(leapYear.fraction, 182.0 / 366), "a leap year has 366 days: \(leapYear.fraction)")
        expect(
            near(
                TimeProgress.year.measure(at: at("2027-07-01 00:00:00"), calendar: utc).fraction, 181.0 / 365),
            "a common year has 365")

        let ny = calendar("America/New_York")
        let dstNoon = TimeProgress.day.measure(
            at: at("2026-03-08 12:00:00", "America/New_York"), calendar: ny)
        expect(near(dstNoon.fraction, 11.0 / 23), "a spring-forward day is 23 hours: \(dstNoon.fraction)")
        expect(near(dstNoon.remaining, 12 * 3600), "twelve real hours remain")
        let fallNoon = TimeProgress.day.measure(
            at: at("2026-11-01 12:00:00", "America/New_York"), calendar: ny)
        expect(near(fallNoon.fraction, 13.0 / 25), "a fall-back day is 25 hours: \(fallNoon.fraction)")
    }

    static func progressFloorsAtTheEdges() {
        let utc = calendar("UTC")
        let start = TimeProgress.day.measure(at: at("2026-10-07 00:00:00"), calendar: utc)
        expect(start.fraction == 0 && start.percent == 0, "midnight is 0%")
        let almost = TimeProgress.day.measure(at: at("2026-10-07 23:59:59"), calendar: utc)
        expect(almost.percent == 99, "a period is never 100% before it ends: \(almost.percent)")
        let next = TimeProgress.day.measure(at: at("2026-10-08 00:00:00"), calendar: utc)
        expect(next.percent == 0, "the next day starts over")
        expect(TimeProgress.allCases.map(\.title) == ["Day", "Week", "Month", "Year"], "titles")
    }

    // MARK: - Alarm

    static func alarmTimesParse() {
        expect(TimeAlarm.parse("07:00") == TimeAlarm(hour: 7, minute: 0), "24-hour")
        expect(TimeAlarm.parse(" 7:30 ") == TimeAlarm(hour: 7, minute: 30), "padded and unpadded")
        expect(TimeAlarm.parse("19:05") == TimeAlarm(hour: 19, minute: 5), "evening")
        expect(TimeAlarm.parse("7pm") == TimeAlarm(hour: 19, minute: 0), "bare pm")
        expect(TimeAlarm.parse("7:30 PM") == TimeAlarm(hour: 19, minute: 30), "spaced uppercase pm")
        expect(TimeAlarm.parse("12am") == TimeAlarm(hour: 0, minute: 0), "12 am is midnight")
        expect(TimeAlarm.parse("12:15 am") == TimeAlarm(hour: 0, minute: 15), "12:15 am")
        expect(TimeAlarm.parse("12pm") == TimeAlarm(hour: 12, minute: 0), "12 pm is noon")
        expect(TimeAlarm.parse("7") == TimeAlarm(hour: 7, minute: 0), "a bare hour")
        expect(TimeAlarm.parse("7.30") == TimeAlarm(hour: 7, minute: 30), "a dotted time")
        for bad in ["", "abc", "25:00", "7:60", "13pm", "0pm", "7:3:1", ":30", "7:", "-1:00", "7:30xm"] {
            expect(TimeAlarm.parse(bad) == nil, "\"\(bad)\" is not a time")
        }
        expect(TimeAlarm(hour: 7, minute: 5).text == "07:05", "stored as 24-hour text")
    }

    static func alarmFiresDailyAcrossMidnight() {
        let utc = calendar("UTC")
        let alarm = TimeAlarm(hour: 7, minute: 0)
        expect(
            alarm.nextFire(after: at("2026-10-05 06:59:59"), calendar: utc) == at("2026-10-05 07:00:00"),
            "later today")
        expect(
            alarm.nextFire(after: at("2026-10-05 07:00:00"), calendar: utc) == at("2026-10-06 07:00:00"),
            "strictly after: the moment itself is spent")
        expect(
            alarm.nextFire(after: at("2026-10-05 23:59:59"), calendar: utc) == at("2026-10-06 07:00:00"),
            "across midnight")
        expect(
            alarm.nextFire(after: at("2026-12-31 08:00:00"), calendar: utc) == at("2027-01-01 07:00:00"),
            "across the new year")
        expect(
            TimeAlarm(hour: 0, minute: 0).nextFire(after: at("2028-02-28 12:00:00"), calendar: utc)
                == at("2028-02-29 00:00:00"), "midnight lands on a leap day")
    }

    static func alarmHandlesDaylightSaving() {
        let ny = calendar("America/New_York")
        let skipped = TimeAlarm(hour: 2, minute: 30)
        let fire = skipped.nextFire(after: at("2026-03-07 03:00:00", "America/New_York"), calendar: ny)
        let parts = fire.map { ny.dateComponents([.month, .day, .hour], from: $0) }
        expect(parts?.month == 3 && parts?.day == 8, "a time lost to spring-forward still rings that day")
        expect(parts?.hour == 3, "at the next valid time: \(String(describing: parts))")
        let following = skipped.nextFire(after: fire!, calendar: ny)
        expect(following == at("2026-03-09 02:30:00", "America/New_York"), "then returns to 2:30")

        let repeated = TimeAlarm(hour: 1, minute: 30)
        let first = repeated.nextFire(after: at("2026-11-01 00:00:00", "America/New_York"), calendar: ny)
        expect(first == at("2026-11-01 05:30:00", "UTC"), "a repeated time rings at its first pass")
        let next = repeated.nextFire(after: first!, calendar: ny)
        expect(next == at("2026-11-02 01:30:00", "America/New_York"), "and not again an hour later")
    }

    static func alarmDueRespectsTheGrace() {
        let utc = calendar("UTC")
        let alarm = TimeAlarm(hour: 7, minute: 0)
        let ring = at("2026-10-05 07:00:00")
        expect(
            alarm.due(since: at("2026-10-05 06:59:00"), now: ring, calendar: utc) == ring,
            "a tick landing exactly on the alarm rings it")
        expect(
            alarm.due(since: ring, now: ring.addingTimeInterval(60), calendar: utc) == nil,
            "a ring is not due twice")
        expect(
            alarm.due(since: at("2026-10-05 06:00:00"), now: at("2026-10-05 06:30:00"), calendar: utc) == nil,
            "nothing is due before the time")
        expect(
            alarm.due(since: at("2026-10-05 06:59:00"), now: at("2026-10-05 07:10:00"), calendar: utc)
                == ring,
            "waking within the grace still rings")
        expect(
            alarm.due(since: at("2026-10-05 06:59:00"), now: at("2026-10-05 07:16:00"), calendar: utc) == nil,
            "waking after the grace stays silent")
        let tomorrow = at("2026-10-06 07:00:00")
        expect(
            alarm.due(since: at("2026-10-03 12:00:00"), now: at("2026-10-06 07:01:00"), calendar: utc)
                == tomorrow,
            "after days asleep only the latest ring counts")
        expect(
            alarm.due(since: at("2026-10-03 12:00:00"), now: at("2026-10-06 12:00:00"), calendar: utc) == nil,
            "and only while it is still recent")
    }

    // MARK: - World clock

    static func worldClockResolvesNamesAndIdentifiers() {
        let zones = TimeWorldClock.resolve("New York, London, Asia/Tokyo, Sydney, Paris")
        expect(zones.count == TimeWorldClock.limit, "four zones at most")
        expect(
            zones.map(\.id) == ["America/New_York", "Europe/London", "Asia/Tokyo", "Australia/Sydney"],
            "cities and identifiers resolve in order: \(zones.map(\.id))")
        expect(zones.map(\.label) == ["New York", "London", "Tokyo", "Sydney"], "labels are the city")

        let messy = TimeWorldClock.resolve("europe/london ; Nowhere Land\nberlin, London, , UTC")
        expect(
            messy.map(\.id) == ["Europe/London", "Europe/Berlin", "GMT"],
            "case-insensitive ids, unknown names skipped, repeats dropped: \(messy.map(\.id))")
        expect(messy.last?.label == "UTC", "UTC labels itself")
        expect(TimeWorldClock.resolve("").isEmpty, "empty text has no zones")
        expect(TimeWorldClock.resolve("Nowhere Land").isEmpty, "only unknown names has no zones")
        expect(TimeWorldClock.resolve("America/New York").first?.id == "America/New_York", "spaced ids")
        expect(TimeWorldClock.resolve("nyc").first?.id == "America/New_York", "calculator aliases resolve")
    }

    static func worldClockOffsetsCrossDates() {
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let evening = at("2026-10-05 20:00:00", "UTC")
        func clock(_ id: String) -> TimeWorldClock {
            TimeWorldClock(id: id, label: id, zone: TimeZone(identifier: id)!)
        }
        expect(clock("Asia/Tokyo").dayOffset(at: evening, home: losAngeles) == 1, "Tokyo is already tomorrow")
        expect(
            clock("Pacific/Honolulu").dayOffset(at: evening, home: losAngeles) == 0,
            "Honolulu shares the date")
        expect(clock("Pacific/Kiritimati").dayOffset(at: evening, home: losAngeles) == 1, "UTC+14")
        let tokyoHome = TimeZone(identifier: "Asia/Tokyo")!
        let early = at("2026-10-05 00:30:00", "UTC")
        expect(
            clock("America/Los_Angeles").dayOffset(at: early, home: tokyoHome) == -1, "LA is still yesterday")
        expect(
            clock("Asia/Tokyo").secondsAhead(at: evening, home: losAngeles) == 16 * 3600,
            "16 hours ahead in October")
        expect(
            clock("Asia/Kolkata").secondsAhead(at: evening, home: losAngeles) == 12 * 3600 + 1800,
            "half-hour zone")
        expect(
            clock("America/Los_Angeles").secondsAhead(at: evening, home: losAngeles) == 0,
            "the home zone is zero ahead")
        let afterFallBack = at("2026-11-02 20:00:00", "UTC")
        expect(
            clock("Asia/Tokyo").secondsAhead(at: afterFallBack, home: losAngeles) == 17 * 3600,
            "an offset follows DST: Los Angeles is back on standard time in November")
        expect(
            clock("Europe/London").dayOffset(at: at("2027-01-01 02:00:00", "UTC"), home: losAngeles) == 1,
            "a new year arrives in London first")
    }
}
