import OnecastPluginKit
import SwiftUI

/// A daily alarm's live state: when it is due, whether it is ringing or snoozed, and the alerts.
@MainActor
@Observable
final class AlarmModel {
    private static let snoozeKey = "snoozeUntil"
    private static let snoozeRange = 1...60
    private static let snoozeFallback = 9
    private static let snoozeAction = "snooze"
    private static let dismissAction = "dismiss"

    private(set) var isRinging = false
    private(set) var snoozeUntil: Date?
    /// Bumped when the model writes a preference itself, which the host is not told about.
    private(set) var revision = 0

    @ObservationIgnored private var preferences: DockWidgetPreferences?
    @ObservationIgnored private var lease: TimeTickLease?
    @ObservationIgnored private var lastChecked = Date()
    @ObservationIgnored private var notificationID: UUID?
    @ObservationIgnored private let player = TimeAlertPlayer()

    init() {
        lease = TimeTickLease(
            needsSeconds: { [weak self] in self?.snoozeUntil != nil },
            onTick: { [weak self] date in self?.tick(date) })
    }

    static func alarm(_ preferences: DockWidgetPreferences) -> TimeAlarm? {
        TimeAlarm.parse(preferences.string("time") ?? "")
    }

    static func label(_ preferences: DockWidgetPreferences) -> String {
        preferences.string("label") ?? "Alarm"
    }

    static func snoozeMinutes(_ preferences: DockWidgetPreferences) -> Int {
        let minutes = preferences.integer("snoozeMinutes") ?? snoozeFallback
        return min(max(minutes, snoozeRange.lowerBound), snoozeRange.upperBound)
    }

    /// The preferences arrive with the first context, so that is when a pending snooze is read.
    func bind(_ preferences: DockWidgetPreferences) {
        guard self.preferences?.instanceID != preferences.instanceID else { return }
        self.preferences = preferences
        snoozeUntil = preferences.string(Self.snoozeKey).flatMap(Double.init).map {
            Date(timeIntervalSinceReferenceDate: $0)
        }
        lease?.reevaluate()
    }

    /// When the alarm next rings: a pending snooze, else its next daily time; nil while off.
    func nextRing(_ preferences: DockWidgetPreferences, after date: Date) -> Date? {
        guard preferences.bool("enabled") else { return nil }
        if let snoozeUntil { return snoozeUntil }
        return Self.alarm(preferences)?.nextFire(after: date, calendar: .autoupdatingCurrent)
    }

    func toggleEnabled() {
        guard let preferences else { return }
        let enabled = !preferences.bool("enabled")
        preferences.set(enabled, for: "enabled")
        if !enabled { stopRinging(clearingSnooze: true) }
        revision += 1
    }

    func snooze() {
        guard let preferences, isRinging else { return }
        stopRinging(clearingSnooze: false)
        let minutes = Self.snoozeMinutes(preferences)
        setSnooze(Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func dismiss() {
        stopRinging(clearingSnooze: true)
    }

    func release() {
        lease?.release()
        lease = nil
        stopRinging(clearingSnooze: false)
    }

    private func tick(_ date: Date) {
        defer { lastChecked = date }
        guard let preferences else { return }
        guard preferences.bool("enabled") else {
            if isRinging || snoozeUntil != nil { stopRinging(clearingSnooze: true) }
            return
        }
        if let until = snoozeUntil, until <= date {
            setSnooze(nil)
            if date.timeIntervalSince(until) <= TimeAlarm.lateGrace { ring(preferences, at: date) }
        } else if let alarm = Self.alarm(preferences),
            alarm.due(since: lastChecked, now: date, calendar: .autoupdatingCurrent) != nil
        {
            ring(preferences, at: date)
        }
    }

    private func ring(_ preferences: DockWidgetPreferences, at date: Date) {
        stopRinging(clearingSnooze: false)
        isRinging = true
        let calendar = Calendar.autoupdatingCurrent
        let time = TimeFormat.clock(date, calendar: calendar, zone: calendar.timeZone, showSeconds: false)
        notificationID = TimeNotificationService.ask(
            title: Self.label(preferences), body: "It's \(time).", tint: .orange,
            actions: [
                NotificationAction(id: Self.snoozeAction, title: "Snooze"),
                NotificationAction(id: Self.dismissAction, title: "Dismiss")
            ]
        ) { [weak self] action in
            if action == Self.snoozeAction {
                self?.snooze()
            } else {
                self?.dismiss()
            }
        }
        if preferences.bool("sound") { player.chimeRepeatedly() }
    }

    private func stopRinging(clearingSnooze: Bool) {
        isRinging = false
        player.stop()
        if let notificationID { TimeNotificationService.withdraw(notificationID) }
        notificationID = nil
        if clearingSnooze, snoozeUntil != nil { setSnooze(nil) }
    }

    private func setSnooze(_ date: Date?) {
        snoozeUntil = date
        preferences?.set(date.map { String($0.timeIntervalSinceReferenceDate) }, for: Self.snoozeKey)
        lease?.reevaluate()
    }
}
