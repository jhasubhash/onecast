import Foundation

/// Who registered a schedule: a plugin (by manifest identifier) or one DockWidget instance.
struct AddonScheduleOwner: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case plugin, dockWidget
    }

    var kind: Kind
    /// A plugin's manifest identifier, or a DockWidget instance's UUID string.
    var id: String
}

/// A schedule a plugin or DockWidget registered in code. The record outlives the code that made it,
/// so Settings can list it and an occurrence missed while Onecast was quit still fires once, late.
struct AddonSchedule: Codable, Hashable, Sendable, Identifiable {
    var owner: AddonScheduleOwner
    /// The plugin or widget's display name, refreshed on every registration.
    var ownerName: String
    var scheduleID: String
    var title: String
    var rule: ScheduleRule
    /// The user's switch in Settings › Scheduler; the owner can neither read nor flip it.
    var isEnabled: Bool
    var lastFired: Date?
    var createdAt: Date

    var id: String { Self.id(owner: owner, scheduleID: scheduleID) }

    static func id(owner: AddonScheduleOwner, scheduleID: String) -> String {
        "\(owner.kind.rawValue):\(owner.id):\(scheduleID)"
    }

    /// What each fire is counted from, as for a `ScheduledTask`.
    var anchor: Date { lastFired ?? createdAt }

    /// A fresh registration, or `existing` re-registered: a changed rule restarts the anchor so the
    /// new rule never replays occurrences the old one already covered or never owed.
    static func registering(
        owner: AddonScheduleOwner, ownerName: String, scheduleID: String, title: String,
        rule: ScheduleRule, existing: AddonSchedule?, now: Date
    ) -> AddonSchedule {
        guard var record = existing else {
            return AddonSchedule(
                owner: owner, ownerName: ownerName, scheduleID: scheduleID, title: title, rule: rule,
                isEnabled: true, lastFired: nil, createdAt: now)
        }
        record.ownerName = ownerName
        record.title = title
        if record.rule != rule {
            record.rule = rule
            record.lastFired = nil
            record.createdAt = now
        }
        return record
    }

    func nextFire(after date: Date, calendar: Calendar) -> Date? {
        guard isEnabled else { return nil }
        return ScheduleEngine.nextFireDate(rule: rule, anchor: anchor, after: date, calendar: calendar)
    }

    /// The latest occurrence owed but not fired by `now`; fired once, late, rather than one per miss.
    func missedOccurrence(now: Date, calendar: Calendar) -> Date? {
        guard isEnabled, anchor < now else { return nil }
        if case .interval(let seconds) = rule {
            // Direct, so a minutely rule after a month asleep never walks every missed minute.
            guard seconds > 0 else { return nil }
            let steps = (now.timeIntervalSince(anchor) / seconds).rounded(.down)
            return steps >= 1 ? anchor.addingTimeInterval(steps * seconds) : nil
        }
        return ScheduleEngine.missedOccurrences(
            rule: rule, anchor: anchor, since: anchor, until: now, calendar: calendar, cap: .max
        ).last
    }

    /// A one-shot that has fired has nothing left to do.
    var isSpent: Bool {
        if case .once = rule { return lastFired != nil }
        return false
    }
}
