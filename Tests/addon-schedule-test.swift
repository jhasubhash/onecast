// Schedules plugins and DockWidgets register in code: re-registration, catch-up and one-shots.
import Foundation

@main
@MainActor
struct AddonScheduleTests {
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
        aFreshRegistrationOwesNothingYet()
        reRegisteringKeepsTheAnchorAndTheUserSwitch()
        aChangedRuleRestartsTheAnchor()
        aDailyMissIsTheLatestOccurrence()
        manyMissedDaysCollapseIntoOne()
        aLongIntervalGapResolvesDirectly()
        aDisabledScheduleNeverFires()
        aOneShotIsSpentOnceFired()
        idsSeparateOwnersAndKinds()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private static let widget = AddonScheduleOwner(kind: .dockWidget, id: "6F1C2A2E-0000-0000-0000-000000000001")

    private static func register(
        _ rule: ScheduleRule, existing: AddonSchedule? = nil, now: Date, title: String = "Reminder"
    ) -> AddonSchedule {
        AddonSchedule.registering(
            owner: widget, ownerName: "LeetCode", scheduleID: "daily", title: title, rule: rule,
            existing: existing, now: now)
    }

    static func aFreshRegistrationOwesNothingYet() {
        let record = register(.daily(hour: 18, minute: 0), now: at(10, 19))
        expect(record.isEnabled, "a new schedule starts enabled")
        expect(record.anchor == at(10, 19), "a new schedule counts from its registration")
        expect(record.missedOccurrence(now: at(10, 19), calendar: calendar) == nil,
               "18:00 already passed at registration is not owed")
        expect(record.nextFire(after: record.anchor, calendar: calendar) == at(11, 18),
               "the first fire is the next 18:00")
    }

    static func reRegisteringKeepsTheAnchorAndTheUserSwitch() {
        var record = register(.daily(hour: 18, minute: 0), now: at(1, 9))
        record.lastFired = at(9, 18)
        record.isEnabled = false
        let again = register(.daily(hour: 18, minute: 0), existing: record, now: at(10, 9), title: "Renamed")
        expect(again.lastFired == at(9, 18), "the same rule keeps its last fire")
        expect(!again.isEnabled, "re-registering never overrides the user's switch")
        expect(again.title == "Renamed", "the title follows the latest registration")
    }

    static func aChangedRuleRestartsTheAnchor() {
        var record = register(.daily(hour: 18, minute: 0), now: at(1, 9))
        record.lastFired = at(5, 18)
        let moved = register(.daily(hour: 7, minute: 30), existing: record, now: at(10, 12))
        expect(moved.lastFired == nil && moved.anchor == at(10, 12), "a new rule counts from now")
        expect(moved.missedOccurrence(now: at(10, 12), calendar: calendar) == nil,
               "a new rule replays nothing the old one owed")
    }

    static func aDailyMissIsTheLatestOccurrence() {
        var record = register(.daily(hour: 18, minute: 0), now: at(1, 9))
        record.lastFired = at(9, 18)
        expect(record.missedOccurrence(now: at(10, 17), calendar: calendar) == nil,
               "nothing is owed before today's 18:00")
        expect(record.missedOccurrence(now: at(10, 20), calendar: calendar) == at(10, 18),
               "today's 18:00 is owed after it passes")
    }

    static func manyMissedDaysCollapseIntoOne() {
        var record = register(.daily(hour: 18, minute: 0), now: at(1, 9))
        record.lastFired = at(2, 18)
        expect(record.missedOccurrence(now: at(10, 9), calendar: calendar) == at(9, 18),
               "a week away owes only the latest occurrence")
    }

    static func aLongIntervalGapResolvesDirectly() {
        let record = register(.interval(seconds: 60), now: at(1, 0))
        let later = at(31, 0).addingTimeInterval(30)
        expect(record.missedOccurrence(now: later, calendar: calendar) == at(31, 0),
               "a minutely rule a month later lands on the last whole minute")
        expect(record.missedOccurrence(now: at(1, 0).addingTimeInterval(59), calendar: calendar) == nil,
               "an interval owes nothing before its first step")
    }

    static func aDisabledScheduleNeverFires() {
        var record = register(.daily(hour: 18, minute: 0), now: at(1, 9))
        record.isEnabled = false
        expect(record.nextFire(after: at(1, 9), calendar: calendar) == nil, "disabled has no next fire")
        expect(record.missedOccurrence(now: at(5, 9), calendar: calendar) == nil, "disabled owes nothing")
    }

    static func aOneShotIsSpentOnceFired() {
        var record = register(.once(at(10, 21)), now: at(10, 9))
        expect(!record.isSpent, "an unfired one-shot is live")
        expect(record.missedOccurrence(now: at(11, 9), calendar: calendar) == at(10, 21),
               "a one-shot passed while away is owed")
        record.lastFired = at(10, 21)
        expect(record.isSpent, "a fired one-shot is spent")
        expect(record.missedOccurrence(now: at(12, 9), calendar: calendar) == nil,
               "a fired one-shot owes nothing more")
    }

    static func idsSeparateOwnersAndKinds() {
        let plugin = AddonScheduleOwner(kind: .plugin, id: widget.id)
        expect(AddonSchedule.id(owner: widget, scheduleID: "a") != AddonSchedule.id(owner: plugin, scheduleID: "a"),
               "the same id under a plugin and a widget never collide")
        expect(AddonSchedule.id(owner: widget, scheduleID: "a") != AddonSchedule.id(owner: widget, scheduleID: "b"),
               "two schedules of one owner stay apart")
    }
}
