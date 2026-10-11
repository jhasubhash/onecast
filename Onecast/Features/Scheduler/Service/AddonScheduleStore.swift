import Foundation

/// The schedules plugins and DockWidgets registered, persisted as JSON in `UserDefaults`.
@MainActor
@Observable
final class AddonScheduleStore {
    private(set) var schedules: [AddonSchedule] = []
    /// Fired after any change lands, so the coordinator re-arms its wake.
    @ObservationIgnored var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let key = "addonSchedules"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() {
        guard let data = defaults.data(forKey: key),
            let stored = try? decoder.decode([AddonSchedule].self, from: data)
        else { return }
        schedules = stored
    }

    func schedule(id: String) -> AddonSchedule? { schedules.first { $0.id == id } }

    func schedules(of owner: AddonScheduleOwner) -> [AddonSchedule] {
        schedules.filter { $0.owner == owner }
    }

    func ownerIDs(kind: AddonScheduleOwner.Kind) -> Set<String> {
        Set(schedules.filter { $0.owner.kind == kind }.map(\.owner.id))
    }

    func upsert(_ schedule: AddonSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            guard schedules[index] != schedule else { return }
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        persist()
    }

    func remove(id: String) {
        guard schedules.contains(where: { $0.id == id }) else { return }
        schedules.removeAll { $0.id == id }
        persist()
    }

    func removeAll(of owner: AddonScheduleOwner) {
        guard schedules.contains(where: { $0.owner == owner }) else { return }
        schedules.removeAll { $0.owner == owner }
        persist()
    }

    /// Switching one back on restarts its anchor, so what it skipped while off never fires late.
    func setEnabled(_ enabled: Bool, id: String, now: Date) {
        guard let index = schedules.firstIndex(where: { $0.id == id }),
            schedules[index].isEnabled != enabled
        else { return }
        schedules[index].isEnabled = enabled
        if enabled { schedules[index].lastFired = now }
        persist()
    }

    func markFired(id: String, at date: Date) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].lastFired = date
        persist()
    }

    private func persist() {
        if let data = try? encoder.encode(schedules) { defaults.set(data, forKey: key) }
        onChange?()
    }
}
