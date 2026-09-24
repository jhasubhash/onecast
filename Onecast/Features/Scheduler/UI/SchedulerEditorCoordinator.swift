import Foundation

/// Creates, edits, and deletes scheduled tasks from the launcher. The editor is an in-palette form
/// (`.schedulerEditor`), never a window or the Scheduler pane; delete confirms through the app's
/// own dialog, not an alert.
@MainActor
final class SchedulerEditorCoordinator {
    let store: ScheduledTaskStore
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore
    /// The draft the editor form binds to, replaced on each open so re-editing shows the right task.
    private(set) var draft = ScheduledTaskDraft(task: nil)

    init(store: ScheduledTaskStore, core: AppCore) {
        self.store = store
        self.core = core
    }

    func createTask() {
        draft = ScheduledTaskDraft(task: nil)
        present()
    }

    func editTask(entryID: String) {
        guard let id = ScheduledTask.id(fromEntryID: entryID), let task = store.task(id: id)
        else { return }
        draft = ScheduledTaskDraft(task: task)
        present()
    }

    /// The launcher reminder fallback: a phrase goes to Onecast, the apps it names, or both at once.
    func scheduleFromPhrase(_ text: String) {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        let now = Date(), calendar = Calendar.current
        // Targets and colour first, so neither cue reaches the time parser or the model's title.
        let (named, rest) = ReminderPhraseParser.splittingTargets(phrase)
        let (tint, request) = ReminderPhraseParser.splittingTint(rest)
        let parsed = ReminderPhraseParser.parse(request, now: now, calendar: calendar)
        let unsure = named == .onecastOnly && ReminderPhraseParser.asksForATarget(request)
        if let parsed, !unsure {
            deliver(parsed.title, rule: parsed.rule, to: named, tint: tint, now: now, calendar: calendar)
            return
        }
        // No time, or a destination asked for in words no cue matched: the model reads it whole.
        Task { [weak self] in
            guard let self else { return }
            if let reading = await ReminderPhraseModel.read(request, now: now, calendar: calendar) {
                // What the parser found outranks the model: its time, and any apps it named.
                let targets = named == .onecastOnly ? reading.targets : named
                let rule = parsed?.rule ?? reading.rule
                deliver(reading.title, rule: rule, to: targets, tint: tint, now: now, calendar: calendar)
            } else if let parsed {
                deliver(parsed.title, rule: parsed.rule, to: named, tint: tint, now: now, calendar: calendar)
            } else if !named.onecast, let title = ReminderPhraseParser.title(of: request) {
                deliver(title, rule: nil, to: named, tint: tint, now: now, calendar: calendar)
            } else {
                core.showMessage("Couldn't find a time in “\(phrase)”.", tone: .danger)
            }
        }
    }

    private func deliver(
        _ title: String, rule: ScheduleRule?, to targets: ReminderTargets, tint: NotificationTint?,
        now: Date, calendar: Calendar
    ) {
        // Checked here, after any model reading, so no reading can reach an app left switched off.
        if let off = targets.apps.first(where: { !core.settings.schedulerReminderApps.contains($0) }) {
            core.showMessage(ReminderAppFailure.notEnabled(off).message, tone: .danger)
            return
        }
        guard rule != nil || !targets.onecast else {
            core.showMessage("Onecast needs a time to remind you of “\(title)”.", tone: .danger)
            return
        }
        if let rule, let refusal = targets.apps.lazy.compactMap({ $0.refusal(of: rule) }).first {
            core.showMessage(refusal, tone: .danger)
            return
        }
        if targets.onecast, let rule {
            store.add(ScheduledTask.notification(title: title, rule: rule, tint: tint, now: now))
        }
        let when = rule.map { " — \(ScheduleFormatter.rule($0))" } ?? ""
        guard !targets.apps.isEmpty else {
            core.showMessage("Reminder set\(when)")
            return
        }
        Task { [weak self] in
            var kept = targets.onecast ? ["Onecast"] : []
            var failures: [String] = []
            for app in targets.apps {
                do throws(ReminderAppFailure) {
                    _ = try await ReminderAppExporter.add(
                        title: title, rule: rule, to: app, now: now, calendar: calendar)
                    kept.append(app.title)
                } catch {
                    failures.append(error.message)
                }
            }
            let added = kept.isEmpty ? "" : "Added to \(Self.joined(kept))\(when)."
            let message = ([added] + failures).filter { !$0.isEmpty }.joined(separator: " ")
            self?.core.showMessage(message, tone: failures.isEmpty ? .success : .danger)
        }
    }

    /// "Onecast, Apple Reminders and Things", in the order the phrase named them.
    private static func joined(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// The form's primary action: persist the draft, then leave the editor.
    func save() {
        guard draft.isValid else { return }
        let task = draft.build()
        let editing = draft.isEditing
        if editing { store.update(task) } else { store.add(task) }
        finish()
        core.showMessage(editing ? "Scheduled task updated" : "Scheduled task created")
    }

    func deleteTask(entryID: String) {
        guard let id = ScheduledTask.id(fromEntryID: entryID), let task = store.task(id: id)
        else { return }
        confirmDelete(task)
    }

    /// Delete the task the editor is open on, from its ⌘K menu; leaves the editor once confirmed.
    func deleteEditing() {
        guard let id = draft.editingID, let task = store.task(id: id) else { return }
        confirmDelete(task) { [weak self] in self?.finish() }
    }

    /// Save or cancel from the form: back to whatever screen opened it, or hide when it was the root.
    func finish() {
        core.paletteCoordinator.closeScreen()
    }

    private func confirmDelete(_ task: ScheduledTask, then onDeleted: (() -> Void)? = nil) {
        Task {
            guard await core.confirm(
                title: "Delete “\(task.name)”?",
                message: "Its global shortcut and launcher references will also be removed.",
                symbol: ScheduledTask.sfSymbol, confirmTitle: "Delete")
            else { return }
            store.remove(id: task.id)
            onDeleted?()
        }
    }

    /// Push over an open launcher so ⎋ returns to it; a bare shortcut opens the form as the root.
    private func present() {
        if core.paletteCoordinator.isVisible {
            core.paletteCoordinator.navigate(to: .schedulerEditor)
        } else {
            core.paletteCoordinator.showPalette(mode: .schedulerEditor)
        }
    }
}
