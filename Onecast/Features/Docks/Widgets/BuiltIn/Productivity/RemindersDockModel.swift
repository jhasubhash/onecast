import EventKit
import Foundation
import OnecastPluginKit

/// One Reminders widget's reminders and edits; EventKit is not `Sendable`, so only values leave.
@MainActor
@Observable
final class RemindersDockModel {
    /// How long a completed reminder offers Undo.
    static let undoWindow: Duration = .seconds(6)
    private static let blockedBeat: Duration = .seconds(3)
    private static let settledBeat: Duration = .seconds(60)

    struct Completion: Equatable {
        let id: String
        let title: String
    }

    private(set) var access: RemindersAccess = Permissions.remindersAccess()
    /// Incomplete reminders of the chosen list, in `DockReminderPlan.ordered` order.
    private(set) var reminders: [DockReminder] = []
    private(set) var isLoaded = false
    /// The named list, when no list on this Mac carries that name.
    private(set) var missingList: String?
    private(set) var lastCompletion: Completion?
    private(set) var failure: String?

    @ObservationIgnored private var preferences: DockWidgetPreferences?
    /// Built after the grant: a store made before it never sees the lists.
    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var changeObserver: NotificationToken?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var undoTask: Task<Void, Never>?

    private var listName: String? {
        let typed = preferences?.string(ProductivityPreferenceName.list)
        let trimmed = typed?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// Views start the first `refresh`, since a build can run inside a view update.
    func attach(_ preferences: DockWidgetPreferences) {
        guard self.preferences == nil else { return }
        self.preferences = preferences
    }

    func stop() {
        undoTask?.cancel()
        undoTask = nil
        changeObserver = nil
        store = nil
        generation += 1
    }

    // MARK: - Reading

    /// TCC sends nothing when a grant changes in Settings, so anything showing `access` re-reads.
    func refresh() {
        access = Permissions.remindersAccess()
        guard access == .granted else {
            changeObserver = nil
            store = nil
            reminders = []
            missingList = nil
            isLoaded = true
            return
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        observeChanges(of: store)

        let lists = store.calendars(for: .reminder)
        let wanted = lists.filter {
            DockReminderPlan.includes(listTitle: $0.title, named: listName)
        }
        guard !wanted.isEmpty else {
            reminders = []
            missingList = lists.isEmpty ? nil : listName
            isLoaded = true
            return
        }
        missingList = nil

        generation += 1
        let ticket = generation
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: wanted)
        Task {
            let fetched = await fetch(matching: predicate, in: store)
            guard ticket == generation else { return }
            reminders = DockReminderPlan.ordered(fetched)
            isLoaded = true
        }
    }

    private func fetch(matching predicate: NSPredicate, in store: EKEventStore) async -> [DockReminder] {
        await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate, completion: Self.collect(into: continuation))
        }
    }

    /// Built off the main actor: EventKit calls it back on a queue of its own.
    nonisolated private static func collect(
        into continuation: CheckedContinuation<[DockReminder], Never>
    ) -> @Sendable ([EKReminder]?) -> Void {
        { reminders in
            continuation.resume(returning: (reminders ?? []).map(Self.reminder(from:)))
        }
    }

    nonisolated private static func reminder(from reminder: EKReminder) -> DockReminder {
        let components = reminder.dueDateComponents
        let due = components.flatMap { ($0.calendar ?? Calendar.current).date(from: $0) }
        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return DockReminder(
            id: reminder.calendarItemIdentifier, title: title.isEmpty ? "Untitled" : title,
            listTitle: reminder.calendar?.title ?? "", due: due,
            hasTime: components?.hour != nil, created: reminder.creationDate)
    }

    private func observeChanges(of store: EKEventStore) {
        guard changeObserver == nil else { return }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        changeObserver = NotificationToken(token, center: center)
    }

    // MARK: - Access

    /// The first-run prompt, raised from the click that asked for it.
    func requestAccess() {
        guard Permissions.remindersAccess() == .notDetermined else {
            Permissions.openRemindersSettings()
            return
        }
        Task {
            _ = await Permissions.requestRemindersAccess()
            refresh()
        }
    }

    /// Reads once, then watches for a grant changed in System Settings, which sends nothing.
    func keepFresh() async {
        refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: access == .granted ? Self.settledBeat : Self.blockedBeat)
            if Permissions.remindersAccess() != access { refresh() }
        }
    }

    // MARK: - Editing

    func complete(_ reminder: DockReminder) {
        guard let store, let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder
        else {
            refresh()
            return
        }
        item.isCompleted = true
        do {
            try store.save(item, commit: true)
        } catch {
            failure = "Couldn't complete it: \(error.localizedDescription)"
            return
        }
        failure = nil
        reminders.removeAll { $0.id == reminder.id }
        offerUndo(Completion(id: reminder.id, title: reminder.title))
    }

    func undoCompletion() {
        guard let completion = lastCompletion else { return }
        clearUndo()
        guard let store, let item = store.calendarItem(withIdentifier: completion.id) as? EKReminder
        else { return }
        item.isCompleted = false
        do {
            try store.save(item, commit: true)
        } catch {
            failure = "Couldn't undo it: \(error.localizedDescription)"
        }
        refresh()
    }

    /// False leaves the typed text where it is, with `failure` saying why.
    func add(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard access == .granted, let store else {
            failure = "Onecast can't reach Reminders."
            return false
        }
        guard let list = targetList(in: store) else {
            failure =
                listName.map { "There is no list named “\($0)” to add to." }
                ?? "Reminders has no default list to add to."
            return false
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = list
        do {
            try store.save(reminder, commit: true)
        } catch {
            failure = "Reminders didn't save it: \(error.localizedDescription)"
            return false
        }
        failure = nil
        refresh()
        return true
    }

    private func targetList(in store: EKEventStore) -> EKCalendar? {
        guard let listName else { return store.defaultCalendarForNewReminders() }
        return store.calendars(for: .reminder).first {
            $0.allowsContentModifications
                && DockReminderPlan.includes(listTitle: $0.title, named: listName)
        }
    }

    func dismissFailure() {
        if failure != nil { failure = nil }
    }

    private func offerUndo(_ completion: Completion) {
        undoTask?.cancel()
        lastCompletion = completion
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.clearUndo()
        }
    }

    private func clearUndo() {
        undoTask?.cancel()
        undoTask = nil
        lastCompletion = nil
    }
}
