import Foundation
import OnecastPluginKit
import os

/// One Hydration widget's live state: today's drinks, the reminder clock and the history file.
@MainActor
@Observable
final class HydrationModel {
    private nonisolated static let logger = Logger(subsystem: "com.onecast", category: "dock-hydration")
    private static let undoWindow: Duration = .seconds(8)
    private static let reminderCardSeconds: TimeInterval = 30
    private static let drankAction = "drank"

    private(set) var log = HydrationLog()
    private(set) var settings = HydrationSettings.standard
    /// When the next nudge fires; nil while reminders are off.
    private(set) var dueAt: Date?
    /// The latest drink added or removed, offered for Undo until the window lapses.
    private(set) var change: HydrationChange?
    private(set) var saveFailure: String?

    @ObservationIgnored private var instanceID: String?
    @ObservationIgnored private var file: HydrationHistoryFile?
    @ObservationIgnored private var watchStart: Date?
    @ObservationIgnored private var lastReminder: Date?
    @ObservationIgnored private var reminderCard: UUID?
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    /// Drives the widget while its tile is on screen: loads history, then follows settings edits.
    func run(_ context: DockWidgetContext) async {
        await attach(context)
        defer { reminderTask?.cancel() }
        for await _ in PersonalDefaults.changes() {
            apply(Self.settings(from: context.preferences))
        }
    }

    func progress(now: Date) -> HydrationProgress {
        settings.progress(for: log.day(containing: now, calendar: .autoupdatingCurrent))
    }

    func drink() {
        let amount = settings.tracksAmounts ? settings.drinkMilliliters : nil
        let entry = HydrationEntry(id: UUID(), date: Date(), milliliters: amount)
        log.add(entry)
        dismissReminderCard()
        record(.added(entry))
    }

    func remove(_ entry: HydrationEntry) {
        guard let removed = log.remove(id: entry.id) else { return }
        record(.removed(removed))
    }

    func undo() {
        guard let change else { return }
        log.revert(change)
        clearChange()
        save()
        reschedule()
    }

    /// The instance left its dock: its history file has no owner any more.
    func didRemove() {
        reminderTask?.cancel()
        undoTask?.cancel()
        dismissReminderCard()
        guard let file else { return }
        persist { file.delete() }
    }

    private func attach(_ context: DockWidgetContext) async {
        let next = Self.settings(from: context.preferences)
        if instanceID != context.instanceID {
            instanceID = context.instanceID
            let file = HydrationHistoryFile(
                directory: Self.historyDirectory, instanceID: context.instanceID)
            self.file = file
            if next.savesHistory {
                log = await Task.detached(priority: .utility) { file.load() }.value
            }
        }
        settings = next
        watchStart = Date()
        reschedule()
    }

    private func apply(_ next: HydrationSettings) {
        guard next != settings else { return }
        let savedBefore = settings.savesHistory
        settings = next
        if savedBefore != next.savesHistory {
            if next.savesHistory { save() } else if let file { persist { file.delete() } }
        }
        reschedule()
    }

    private func record(_ change: HydrationChange) {
        self.change = change
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.change = nil
        }
        save()
        reschedule()
    }

    private func clearChange() {
        undoTask?.cancel()
        change = nil
    }

    private func reschedule() {
        reminderTask?.cancel()
        reminderTask = nil
        guard let watchStart else {
            dueAt = nil
            return
        }
        dueAt = HydrationReminder.due(
            lastDrink: log.lastDrink, watchStart: watchStart, lastReminder: lastReminder,
            minutes: settings.reminderMinutes)
        guard let due = dueAt else { return }
        reminderTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HydrationReminder.secondsUntil(due, now: Date())))
            guard !Task.isCancelled else { return }
            self?.remind()
        }
    }

    private func remind() {
        let presenter = AppCore.shared.notificationPresenter
        dismissReminderCard()
        let spec = NotificationSpec(
            id: UUID(), title: "Time to drink water",
            body: HydrationFormat.reminderBody(progress(now: Date()), locale: .autoupdatingCurrent),
            style: .card, corner: .topTrailing, dwell: Self.reminderCardSeconds,
            actions: [NotificationAction(id: Self.drankAction, title: "I drank water")],
            tint: .blue)
        reminderCard = spec.id
        presenter.post(spec, playsSound: true) { [weak self] action in
            guard action == Self.drankAction else { return }
            self?.drink()
        }
        lastReminder = Date()
        reschedule()
    }

    private func dismissReminderCard() {
        guard let reminderCard else { return }
        AppCore.shared.notificationPresenter.dismiss(reminderCard)
        self.reminderCard = nil
    }

    private func save() {
        guard settings.savesHistory, let file else { return }
        let snapshot = log
        persist { try file.save(snapshot) }
    }

    /// Writes run one after another off-main, so a late save can never land over a newer one.
    private func persist(_ work: @escaping @Sendable () throws -> Void) {
        let previous = writeTask
        writeTask = Task { [weak self] in
            await previous?.value
            let failure = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try work()
                    return nil
                } catch {
                    let message = error.localizedDescription
                    Self.logger.error("Hydration history write failed: \(message, privacy: .public)")
                    return message
                }
            }.value
            self?.saveFailure = failure
        }
    }

    private static var historyDirectory: URL {
        AppPaths.applicationSupport().appending(path: "Docks/Hydration", directoryHint: .isDirectory)
    }

    private static func settings(from preferences: DockWidgetPreferences) -> HydrationSettings {
        HydrationSettings(
            reminder: preferences.string("reminderMinutes"),
            savesHistory: preferences.bool("saveHistory"),
            tracksAmounts: preferences.bool("trackAmounts"),
            drinkSize: preferences.string("drinkSize"),
            goalMilliliters: preferences.string("dailyGoal"),
            goalDrinks: preferences.string("dailyGoalDrinks"))
    }
}
