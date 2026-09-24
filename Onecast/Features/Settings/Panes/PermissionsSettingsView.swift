import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var calendarAccess = Permissions.calendarAccess()
    @State private var remindersAccess = Permissions.remindersAccess()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Label(
                        accessibilityTrusted ? "Granted" : "Not granted",
                        systemImage: accessibilityTrusted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
                } label: {
                    SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                    Text("Lets Onecast paste a clipboard item into the app you were using.")
                }

                LabeledContent {
                    Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                        Permissions.openAccessibilitySettings()
                    }
                } label: {
                    Text(accessibilityTrusted ? "Manage in System Settings" : "Grant access")
                    Text("Opens Privacy & Security › Accessibility.")
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            } footer: {
                Text("Access Onecast needs to work with other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Label(calendarStatus.title, systemImage: calendarStatus.symbol)
                        .foregroundStyle(calendarStatus.tint)
                } label: {
                    SettingsRowTitle(.permissionsCalendars, "Calendars")
                    Text("Lets Onecast find the join link for the meeting you are about to be in.")
                }

                LabeledContent {
                    Button(calendarNeedsPrompt ? "Grant Access…" : "Open…") {
                        // Settings lists no app TCC was never asked about, so asking is the way in.
                        if calendarNeedsPrompt {
                            core.calendarCoordinator.setCalendarEnabled(true)
                        } else {
                            Permissions.openCalendarSettings()
                        }
                    }
                } label: {
                    Text(calendarNeedsPrompt ? "Grant access" : "Manage in System Settings")
                    Text(
                        calendarNeedsPrompt
                            ? "Turns the calendar on, then asks macOS for access."
                            : "Opens Privacy & Security › Calendars.")
                }
            } header: {
                SettingsSectionHeader(.permissionsCalendars)
            }

            Section {
                LabeledContent {
                    let status = Self.status(of: remindersAccess == .granted, asked: remindersAccess != .notDetermined)
                    Label(status.title, systemImage: status.symbol)
                        .foregroundStyle(status.tint)
                } label: {
                    SettingsRowTitle(.permissionsReminders, "Reminders")
                    Text("Lets Onecast add a reminder to Apple Reminders when you ask it to.")
                }

                LabeledContent {
                    Button(remindersAccess == .notDetermined ? "Grant Access…" : "Open…") {
                        if remindersAccess == .notDetermined {
                            Task {
                                _ = await Permissions.requestRemindersAccess()
                                refresh()
                            }
                        } else {
                            Permissions.openRemindersSettings()
                        }
                    }
                } label: {
                    Text(remindersAccess == .notDetermined ? "Grant access" : "Manage in System Settings")
                    Text(
                        remindersAccess == .notDetermined
                            ? "Asks macOS for access to Apple Reminders."
                            : "Opens Privacy & Security › Reminders.")
                }
            } header: {
                SettingsSectionHeader(.permissionsReminders)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var calendarNeedsPrompt: Bool { calendarAccess == .notDetermined }

    private var calendarStatus: (title: String, symbol: String, tint: Color) {
        Self.status(of: calendarAccess == .granted, asked: calendarAccess != .notDetermined)
    }

    private static func status(of granted: Bool, asked: Bool) -> (title: String, symbol: String, tint: Color) {
        if granted { return ("Granted", "checkmark.circle.fill", .green) }
        return asked
            ? ("Not granted", "exclamationmark.triangle.fill", .orange)
            : ("Not asked yet", "questionmark.circle.fill", .secondary)
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let access = Permissions.calendarAccess()
        if access != calendarAccess { calendarAccess = access }
        let reminders = Permissions.remindersAccess()
        if reminders != remindersAccess { remindersAccess = reminders }
    }
}
