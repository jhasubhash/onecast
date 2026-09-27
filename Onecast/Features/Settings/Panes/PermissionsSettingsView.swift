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
                    HStack(spacing: Theme.Spacing.lg) {
                        statusLabel(accessibilityStatus)
                        Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                        .help("Opens Privacy & Security › Accessibility.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path:
                                "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                            Text("Pastes into the app you were using.")
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    HStack(spacing: Theme.Spacing.lg) {
                        statusLabel(calendarStatus)
                        Button(calendarNeedsPrompt ? "Grant Access…" : "Open…") {
                            // Settings lists no app TCC was never asked about, so asking is the way in.
                            if calendarNeedsPrompt {
                                core.calendarCoordinator.setCalendarEnabled(true)
                            } else {
                                Permissions.openCalendarSettings()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(path: "/System/Applications/Calendar.app")
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsCalendars, "Calendars")
                            Text("Finds the join link for your next meeting.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsCalendars)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        statusLabel(remindersStatus)
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
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(path: "/System/Applications/Reminders.app")
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsReminders, "Reminders")
                            Text("Adds the reminders you send to Apple Reminders.")
                                .foregroundStyle(.secondary)
                        }
                    }
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

    private var accessibilityStatus: (title: String, symbol: String, tint: Color) {
        Self.status(of: accessibilityTrusted, asked: true)
    }

    private var calendarStatus: (title: String, symbol: String, tint: Color) {
        Self.status(of: calendarAccess == .granted, asked: calendarAccess != .notDetermined)
    }

    private var remindersStatus: (title: String, symbol: String, tint: Color) {
        Self.status(of: remindersAccess == .granted, asked: remindersAccess != .notDetermined)
    }

    private static func status(of granted: Bool, asked: Bool) -> (title: String, symbol: String, tint: Color) {
        if granted { return ("Granted", "checkmark.circle.fill", .green) }
        return asked
            ? ("Not granted", "exclamationmark.triangle.fill", .orange)
            : ("Not asked yet", "questionmark.circle.fill", .secondary)
    }

    private func statusLabel(_ status: (title: String, symbol: String, tint: Color)) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: status.symbol)
                .accessibilityHidden(true)
            Text(status.title)
        }
        .foregroundStyle(status.tint)
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

private struct PermissionSettingsIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: IconCache.icon(forFile: path))
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .id(IconCache.style.generation)
            .frame(
                width: SettingsListMetrics.iconSize,
                height: SettingsListMetrics.iconSize
            )
            .accessibilityHidden(true)
    }
}
