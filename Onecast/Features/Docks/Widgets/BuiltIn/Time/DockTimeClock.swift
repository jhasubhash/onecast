import Foundation

/// One shared tick for every time widget: per second only while one shows seconds, else per minute.
@MainActor
@Observable
final class DockTimeClock {
    /// Slack the system may add to a wake, kept under a display frame.
    private static let wakeTolerance: Duration = .milliseconds(20)

    /// The latest tick, which lands every second or every minute depending on who is watching.
    private(set) var now = Date()
    /// Moves once a minute whatever the tick rate, for tiles that show no seconds.
    private(set) var minute = Date()

    private struct Subscription {
        let needsSeconds: @MainActor () -> Bool
        let onTick: @MainActor (Date) -> Void
    }

    @ObservationIgnored private var subscriptions: [UUID: Subscription] = [:]
    @ObservationIgnored private var sleeper: Task<Void, Never>?
    @ObservationIgnored private var observers: [NotificationToken] = []

    init() {}

    /// `needsSeconds` is asked before every sleep, so the rate follows what the widgets show now.
    func subscribe(
        needsSeconds: @escaping @MainActor () -> Bool, onTick: @escaping @MainActor (Date) -> Void
    ) -> UUID {
        let id = UUID()
        if subscriptions.isEmpty { observeSystem() }
        subscriptions[id] = Subscription(needsSeconds: needsSeconds, onTick: onTick)
        schedule()
        return id
    }

    func unsubscribe(_ id: UUID) {
        guard subscriptions.removeValue(forKey: id) != nil else { return }
        if subscriptions.isEmpty { observers.removeAll() }
        schedule()
    }

    /// Re-picks the tick rate after a widget's own state changed what it needs.
    func reevaluate() {
        schedule()
    }

    private func schedule() {
        sleeper?.cancel()
        sleeper = nil
        guard !subscriptions.isEmpty else { return }
        let step: TimeInterval = subscriptions.values.contains(where: { $0.needsSeconds() }) ? 1 : 60
        let boundary = TimeTick.nextBoundary(after: Date(), step: step)
        sleeper = Task { [weak self] in
            let wait = Duration.seconds(boundary.timeIntervalSinceNow)
            try? await Task.sleep(for: wait, tolerance: Self.wakeTolerance)
            guard !Task.isCancelled else { return }
            self?.fire(at: boundary)
        }
    }

    /// A wake that lands a hair before its boundary still reports the boundary.
    private func fire(at boundary: Date) {
        publish(max(Date(), boundary))
        for subscription in subscriptions.values { subscription.onTick(now) }
        schedule()
    }

    private func publish(_ date: Date) {
        if TimeTick.minuteIndex(date) != TimeTick.minuteIndex(minute) { minute = date }
        now = date
    }

    /// A settings edit can change what a widget shows, and a zone or clock change moves the time.
    private func observeSystem() {
        let center = NotificationCenter.default
        let reschedule = center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        }
        let timeChanged: [Notification.Name] = [.NSSystemTimeZoneDidChange, .NSSystemClockDidChange]
        var tokens = [NotificationToken(reschedule, center: center)]
        for name in timeChanged {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    let moment = Date()
                    self?.minute = moment
                    self?.publish(moment)
                    self?.schedule()
                }
            }
            tokens.append(NotificationToken(token, center: center))
        }
        observers = tokens
    }
}
