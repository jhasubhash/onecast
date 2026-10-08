import AppKit
import SwiftUI

/// The Presentation pane: the switch, how windows are arranged, per-display resolutions, hooks.
struct PresentationSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .presentationPresentation,
                enableTitle: "Enable Presentation Mode",
                enableSubtitle:
                    "One click puts other apps away, sizes the front window for screen sharing and can "
                    + "switch the display to a larger-text resolution, then puts everything back.",
                launcherSubtitle: "Find Start, Stop and Toggle Presentation in launcher search.",
                isEnabled: $settings.presentationEnabled,
                showsInLauncher: $settings.presentationShowInLauncher)

            PresentationStatusSection()
                .settingsEnabled(settings.presentationEnabled)

            Section {
                Picker(selection: $settings.presentationWindowSize) {
                    ForEach(PresentationWindowSize.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.presentationWindows, "Presented window")
                    Text("How the front app's window is sized on the display you present on.")
                }
                if settings.presentationWindowSize == .margin {
                    Picker(selection: $settings.presentationMarginPercent) {
                        ForEach(PresentationMargin.choices, id: \.self) { Text("\($0)%").tag($0) }
                    } label: {
                        SettingsRowTitle(.presentationWindows, "Margin")
                        Text("Space left free on each side, so the Dock and desktop stay in view.")
                    }
                }
                Picker(selection: $settings.presentationOtherApps) {
                    ForEach(PresentationOtherApps.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.presentationWindows, "Other apps")
                    Text("Put back exactly as they were when the presentation ends.")
                }
                if settings.presentationOtherApps != .leave {
                    Picker(selection: $settings.presentationScope) {
                        ForEach(PresentationScope.allCases) { Text($0.title).tag($0) }
                    } label: {
                        SettingsRowTitle(.presentationWindows, "Put away windows on")
                        Text(scopeSubtitle)
                    }
                }
                Picker(selection: $settings.presentationAppSwitch) {
                    ForEach(PresentationAppSwitch.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.presentationWindows, "When you switch apps")
                    Text("What happens to an app you bring forward while presenting.")
                }
                Toggle(isOn: $settings.presentationRestoresWindows) {
                    SettingsRowTitle(.presentationWindows, "Restore windows afterwards")
                    Text("Moves presented windows back to where they were.")
                }
                PresentationIgnoredAppsRows()
            } header: {
                SettingsSectionHeader(.presentationWindows)
            }
            .settingsEnabled(settings.presentationEnabled)

            PresentationResolutionSection()
                .settingsEnabled(settings.presentationEnabled)

            Section {
                Toggle(isOn: $settings.presentationHidesDocks) {
                    SettingsRowTitle(.presentationWhilePresenting, "Hide custom docks")
                    Text("Keeps widgets such as your calendar and stocks off the shared screen.")
                }
                Toggle(isOn: $settings.presentationShowsMenuBarItem) {
                    SettingsRowTitle(.presentationWhilePresenting, "Show in the menu bar")
                    Text("A recording sign with the elapsed time, and Stop Presentation.")
                }
                Toggle(isOn: $settings.presentationKeepsDisplayAwake) {
                    SettingsRowTitle(.presentationWhilePresenting, "Keep the display awake")
                    Text("Stops the screen dimming or sleeping mid-presentation.")
                }
            } header: {
                SettingsSectionHeader(.presentationWhilePresenting)
            }
            .settingsEnabled(settings.presentationEnabled)

            Section {
                TextField(text: $settings.presentationStartShortcut, prompt: Text("Shortcut name")) {
                    SettingsRowTitle(.presentationShortcuts, "When presenting starts")
                    Text("An Apple Shortcut to run, such as one that turns on Do Not Disturb.")
                }
                TextField(text: $settings.presentationEndShortcut, prompt: Text("Shortcut name")) {
                    SettingsRowTitle(.presentationShortcuts, "When presenting ends")
                    Text("An Apple Shortcut to run, such as one that turns Do Not Disturb off.")
                }
            } header: {
                SettingsSectionHeader(.presentationShortcuts)
            }
            .settingsEnabled(settings.presentationEnabled)

            FeatureCommandsSection(owner: .presentation, anchor: .presentationCommands)
                .settingsEnabled(settings.presentationEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.presentation)
        .releasesFocusOnOutsideClick()
    }

    private var scopeSubtitle: String {
        switch settings.presentationScope {
        case .everywhere:
            "Every Space and display. Minimized apps are hidden too, so other Spaces stay clear."
        case .currentSpace: "Only what each display shows now; other Spaces are left as they are."
        case .presentationDisplay: "Only windows on the display being shared; other displays stay."
        }
    }
}

/// Whether a presentation is running, with the button that starts or ends one.
private struct PresentationStatusSection: View {
    @Environment(PresentationCoordinator.self) private var coordinator

    var body: some View {
        Section {
            SettingsRow(title: "Presentation", subtitle: status) {
                Button(coordinator.isPresenting ? "End Presentation" : "Start Presentation") {
                    coordinator.toggle()
                }
                .disabled(coordinator.isBusy)
            }
        }
    }

    private var status: String {
        switch coordinator.phase {
        case .idle: "Off. Starting presents the app in front of Settings once you switch to it."
        case .starting: "Starting…"
        case .stopping: "Ending…"
        case .presenting:
            [coordinator.presentedApp?.localizedName, coordinator.displayName]
                .compactMap(\.self).joined(separator: " on ")
        }
    }
}

/// One resolution picker per connected display, each remembering its own choice.
private struct PresentationResolutionSection: View {
    @Environment(PresentationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var displays: [PresentationCoordinator.DisplayChoices] = []

    var body: some View {
        Section {
            ForEach(displays) { display in
                Picker(selection: selection(for: display.key)) {
                    Text("Don’t change").tag(String?.none)
                    ForEach(display.choices, id: \.id) { mode in
                        Text(mode.title).tag(String?.some(mode.id))
                    }
                } label: {
                    Text(display.name)
                    if let current = display.current {
                        Text("Now \(current.title)")
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.presentationDisplays)
        } footer: {
            Text(
                "A smaller size makes text bigger for the people watching. The display goes back to "
                    + "its own resolution when the presentation ends, or if Onecast quits.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear { displays = coordinator.displayChoices() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            displays = coordinator.displayChoices()
        }
    }

    private func selection(for key: String) -> Binding<String?> {
        Binding(
            get: { settings.presentationResolutions[key] },
            set: { coordinator.setResolution($0, forDisplay: key) })
    }
}

/// The leave-alone list: installed apps only, so a default naming an absent app adds no row.
private struct PresentationIgnoredAppsRows: View {
    @Environment(PresentationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsRow(
            title: "Apps to leave alone",
            subtitle: "Never presented, hidden or resized. Keeps the meeting app and its controls up.",
            subtitleLineLimit: 2, anchor: .presentationWindows
        ) {
            Button("Add App…") { coordinator.chooseIgnoredApps() }
        }
        ForEach(installed, id: \.bundleID) { app in
            SettingsScopeRow(scope: app.name, path: app.path, isMissing: false) {
                coordinator.removeIgnoredApp(app.bundleID)
            }
        }
    }

    private var installed: [(bundleID: String, name: String, path: String)] {
        settings.presentationIgnoredApps.compactMap { bundleID in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
            return (bundleID, (name as NSString).deletingPathExtension, url.path)
        }
    }
}
