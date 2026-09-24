import SwiftUI

/// The scheduler pane: the master switch, then the user's own scheduled tasks.
struct SchedulerSettingsView: View {
    @Environment(ScheduledTaskStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var editor: EditorTarget?
    @State private var pendingDeletion: ScheduledTask?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .schedulerScheduler,
                enableTitle: "Enable scheduler",
                enableSubtitle:
                    "Runs a script or posts a notification on a schedule, catching up on fires missed "
                    + "while the app was closed.",
                launcherSubtitle: "Find your tasks in launcher search to run them on demand.",
                isEnabled: $settings.schedulerEnabled,
                showsInLauncher: $settings.schedulerShowInLauncher)

            Section {
                if store.tasks.isEmpty {
                    Text("Add one to run it on a schedule, or on demand from the launcher.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTasks) { task in
                        ScheduledTaskSettingsRow(
                            task: task,
                            showsInLauncher: settings.schedulerShowInLauncher,
                            isEnabled: Binding(
                                get: { task.isEnabled },
                                set: { store.setEnabled($0, for: task.id) }),
                            onEdit: { editor = EditorTarget(task: task) },
                            onDelete: { pendingDeletion = task })
                    }
                }
                Button {
                    editor = EditorTarget(task: nil)
                } label: {
                    SettingsRowTitle(.schedulerScheduler, "Create Scheduled Task")
                }
            } footer: {
                Text(
                    "Pick when it fires and what it does. A task keeps its own last-fired anchor, so "
                        + "editing the schedule never double-fires.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.schedulerEnabled)

            Section {
                Toggle(isOn: $settings.schedulerPlaysSound) {
                    SettingsRowTitle(.schedulerNotifications, "Play a sound")
                    Text("Chime when a scheduled notification or a script's finish toast appears.")
                }
            } header: {
                SettingsSectionHeader(.schedulerNotifications)
            }
            .settingsEnabled(settings.schedulerEnabled)

            ReminderAppsSection()
                .settingsEnabled(settings.schedulerEnabled)

            FeatureCommandsSection(owner: .scheduler, anchor: .schedulerCommands)
                .settingsEnabled(settings.schedulerEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.scheduler)
        .releasesFocusOnOutsideClick()
        .sheet(item: $editor) { target in
            SchedulerTaskEditorSheet(task: target.task, dismiss: { editor = nil })
        }
        .alert(item: $pendingDeletion) { task in
            Alert(
                title: Text("Delete “\(task.name)”?"),
                message: Text("Its global shortcut and launcher references will also be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    store.remove(id: task.id)
                },
                secondaryButton: .cancel())
        }
    }

    private var sortedTasks: [ScheduledTask] {
        store.tasks.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

/// The apps a reminder phrase may write to, each off until switched on; Reminders asks macOS then.
private struct ReminderAppsSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var remindersAccess = Permissions.remindersAccess()

    var body: some View {
        Section {
            Toggle(isOn: binding(.appleReminders)) {
                SettingsRowTitle(.schedulerReminderApps, "Apple Reminders")
                Text("Say “…, add it to Apple Reminders” to keep a reminder there instead.")
            }
            if remindersAccess == .denied {
                SettingsRow(
                    title: "Reminders access is off",
                    subtitle: "Turn Onecast on under Privacy & Security ▸ Reminders."
                ) {
                    Button("Open System Settings…") { Permissions.openRemindersSettings() }
                }
            }
            Toggle(isOn: binding(.things)) {
                SettingsRowTitle(.schedulerReminderApps, "Things")
                Text(
                    ReminderAppExporter.isInstalled(.things)
                        ? "Say “…, add it to Things” to add a to-do that reminds you then."
                        : "Things isn't installed on this Mac.")
            }
            .disabled(!ReminderAppExporter.isInstalled(.things) && !isOn(.things))
        } header: {
            SettingsSectionHeader(.schedulerReminderApps)
        } footer: {
            Text("Repeats every few minutes stay in Onecast, and Things takes one-time reminders only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { remindersAccess = Permissions.remindersAccess() }
    }

    private func isOn(_ app: ReminderApp) -> Bool { settings.schedulerReminderApps.contains(app) }

    private func binding(_ app: ReminderApp) -> Binding<Bool> {
        Binding(get: { isOn(app) }, set: { set(app, on: $0) })
    }

    /// Switching Reminders on is the gesture macOS asks from; a refusal leaves it off.
    private func set(_ app: ReminderApp, on: Bool) {
        guard on else {
            settings.schedulerReminderApps.remove(app)
            return
        }
        // Denied, only System Settings can help, and the row under the toggle says so.
        if app == .appleReminders, remindersAccess == .denied { return }
        settings.schedulerReminderApps.insert(app)
        guard app == .appleReminders, remindersAccess == .notDetermined else { return }
        Task {
            let granted = await Permissions.requestRemindersAccess()
            remindersAccess = Permissions.remindersAccess()
            if !granted { settings.schedulerReminderApps.remove(app) }
        }
    }
}

private struct EditorTarget: Identifiable {
    let id = UUID()
    let task: ScheduledTask?
}

private struct ScheduledTaskSettingsRow: View {
    let task: ScheduledTask
    let showsInLauncher: Bool
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: task.name, subtitle: ScheduleFormatter.summary(of: task)) {
            Image(systemName: ScheduledTask.sfSymbol)
        } trailing: {
            // An alias only reaches the ranker through the launcher slice, so it dims with it.
            AliasField(key: task.entryID, name: task.name)
                .settingsEnabled(task.isEnabled && showsInLauncher)

            // A disabled task's shortcut fires into the coordinator's refusal, so it dims too.
            ShortcutRecorder(action: .scheduledTask(id: task.id))
                .settingsEnabled(task.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Task")
            .accessibilityLabel("Edit \(task.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Task")
            .accessibilityLabel("Delete \(task.name)")

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Enabled")
                .accessibilityLabel("Enable \(task.name)")
        }
    }
}
