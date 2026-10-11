import Foundation
import OnecastPluginKit

/// Onecast's notifications and scheduler as plugins and DockWidgets see them. A schedule fires only
/// while the code that registered it is loaded and holds a handler; its record persists, so the
/// occurrence missed meanwhile fires once, late, when the owner registers again.
@MainActor
@Observable
final class AddonScheduleCoordinator {
    private let store: AddonScheduleStore
    private let notifications: NotificationPresenter
    private let calendar = Calendar.current

    /// The schedules whose owner is loaded now; Settings marks the rest as not running.
    private(set) var liveIDs: Set<String> = []

    @ObservationIgnored private var handlers: [String: OnecastHostServices.FireHandler] = [:]
    /// The one pending wake for every add-on schedule, as `SchedulerCoordinator` keeps for tasks.
    @ObservationIgnored private var timer: Task<Void, Never>?

    /// A fire this far behind its occurrence reports `isLate`.
    private static let lateAfter: TimeInterval = 60

    init(store: AddonScheduleStore, notifications: NotificationPresenter) {
        self.store = store
        self.notifications = notifications
    }

    func start() {
        store.onChange = { [weak self] in self?.reschedule() }
        store.load()
    }

    var schedules: [AddonSchedule] { store.schedules }

    func nextFire(of schedule: AddonSchedule) -> Date? {
        schedule.nextFire(after: Date(), calendar: calendar)
    }

    func setEnabled(_ enabled: Bool, id: String) {
        store.setEnabled(enabled, id: id, now: Date())
    }

    func ownerIDs(kind: AddonScheduleOwner.Kind) -> Set<String> { store.ownerIDs(kind: kind) }

    func hasSchedules(_ owner: AddonScheduleOwner) -> Bool { !store.schedules(of: owner).isEmpty }

    // MARK: - Services

    /// The services handed to one owner; every schedule it registers is filed under it.
    func services(for owner: AddonScheduleOwner, name: String) -> OnecastHostServices {
        OnecastHostServices(
            notify: { [weak self] notification, onAction in
                self?.notify(notification, onAction: onAction) ?? ""
            },
            dismissNotification: { [weak self] id in self?.dismissNotification(id) },
            schedule: { [weak self] schedule, fire in
                self?.register(schedule, owner: owner, ownerName: name, fire: fire)
            },
            unschedule: { [weak self] id in self?.unregister(scheduleID: id, owner: owner) })
    }

    @discardableResult
    func notify(_ notification: OnecastNotification, onAction: OnecastHostServices.ActionHandler?) -> String {
        let spec = NotificationSpec(
            id: UUID(), title: notification.title, body: notification.body,
            style: notification.actions.isEmpty ? .banner : .card, corner: .topTrailing,
            dwell: notification.dwell,
            actions: notification.actions.map { NotificationAction(id: $0.id, title: $0.title) },
            tint: notification.tint.flatMap { NotificationTint(rawValue: $0.rawValue) })
        let id = notifications.post(
            spec, playsSound: notification.playsSound, onAction: onAction.map { handler in { handler($0) } })
        return id.uuidString
    }

    func dismissNotification(_ id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        notifications.dismiss(uuid)
    }

    func register(
        _ schedule: OnecastSchedule, owner: AddonScheduleOwner, ownerName: String,
        fire: @escaping OnecastHostServices.FireHandler
    ) {
        let id = AddonSchedule.id(owner: owner, scheduleID: schedule.id)
        let record = AddonSchedule.registering(
            owner: owner, ownerName: ownerName, scheduleID: schedule.id, title: schedule.title,
            rule: Self.rule(schedule.rule), existing: store.schedule(id: id), now: Date())
        handlers[id] = fire
        liveIDs.insert(id)
        store.upsert(record)
        reschedule()
    }

    func unregister(scheduleID: String, owner: AddonScheduleOwner) {
        let id = AddonSchedule.id(owner: owner, scheduleID: scheduleID)
        handlers[id] = nil
        liveIDs.remove(id)
        store.remove(id: id)
    }

    /// The owner's code was unloaded: its schedules stop firing but are kept for its return.
    func detach(_ owner: AddonScheduleOwner) {
        for schedule in store.schedules(of: owner) {
            handlers[schedule.id] = nil
            liveIDs.remove(schedule.id)
        }
        reschedule()
    }

    /// The owner is gone for good: a removed DockWidget instance or an uninstalled plugin.
    func forget(_ owner: AddonScheduleOwner) {
        detach(owner)
        store.removeAll(of: owner)
    }

    private static func rule(_ rule: OnecastScheduleRule) -> ScheduleRule {
        switch rule {
        case .once(let date): .once(date)
        case .interval(let seconds): .interval(seconds: seconds)
        case .daily(let hour, let minute): .daily(hour: hour, minute: minute)
        case .weekly(let weekdays, let hour, let minute):
            .weekly(weekdays: weekdays, hour: hour, minute: minute)
        }
    }

    // MARK: - Firing

    private func reschedule() {
        timer?.cancel()
        let target = store.schedules
            .filter { handlers[$0.id] != nil }
            .compactMap { $0.nextFire(after: $0.anchor, calendar: calendar) }
            .min()
        guard let target else {
            timer = nil
            return
        }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, target.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.fireDue()
        }
    }

    /// Several missed occurrences collapse into one late fire of the latest.
    private func fireDue() {
        let now = Date()
        for schedule in store.schedules {
            guard let handler = handlers[schedule.id],
                let next = schedule.nextFire(after: schedule.anchor, calendar: calendar),
                next <= now.addingTimeInterval(0.5)
            else { continue }
            let date = schedule.missedOccurrence(now: now, calendar: calendar) ?? next
            store.markFired(id: schedule.id, at: date)
            if store.schedule(id: schedule.id)?.isSpent == true {
                handlers[schedule.id] = nil
                liveIDs.remove(schedule.id)
                store.remove(id: schedule.id)
            }
            handler(
                OnecastScheduleFire(
                    scheduleID: schedule.scheduleID, date: date,
                    isLate: now.timeIntervalSince(date) > Self.lateAfter))
        }
        reschedule()
    }
}
