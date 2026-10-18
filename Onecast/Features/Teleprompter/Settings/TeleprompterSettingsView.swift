import SwiftUI

struct TeleprompterSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.teleprompterEnabled) {
                    SettingsRowTitle(.teleprompterTeleprompter, "Enable Teleprompter")
                    Text("Read a script from an overlay under the notch, hidden from screen shares and recordings.")
                }
                LabeledContent {
                    Button("Open Teleprompter…", action: core.teleprompterCoordinator.openEditor)
                } label: {
                    Text("Script")
                    Text("Paste a script, or run Teleprompt Selected Text from any app.")
                }
                .settingsEnabled(settings.teleprompterEnabled)
            } header: {
                SettingsSectionHeader(.teleprompterTeleprompter)
            }

            Section {
                Picker(selection: $settings.teleprompterMode) {
                    ForEach(TeleprompterMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.teleprompterGuidance, "Guidance mode")
                    Text(modeDetail)
                }
                LabeledContent {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(settings.teleprompterSpeed) },
                                set: { settings.teleprompterSpeed = Int($0) }),
                            in: Double(TeleprompterPace.range.lowerBound)...Double(TeleprompterPace.range.upperBound),
                            step: 10)
                        Text("\(settings.teleprompterSpeed) wpm")
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .frame(width: 260)
                } label: {
                    SettingsRowTitle(.teleprompterGuidance, "Speed")
                    Text("How fast Classic and Voice-Activated scroll.")
                }
                .disabled(settings.teleprompterMode == .wordTracking)
            } header: {
                SettingsSectionHeader(.teleprompterGuidance)
            }
            .settingsEnabled(settings.teleprompterEnabled)

            Section {
                Picker(selection: $settings.teleprompterPlacement) {
                    ForEach(TeleprompterPlacement.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.teleprompterAppearance, "Position")
                }
                LabeledContent {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(settings.teleprompterTextSize) },
                                set: { settings.teleprompterTextSize = Int($0) }),
                            in: Double(TeleprompterPace.textSizes.lowerBound)...Double(TeleprompterPace.textSizes.upperBound),
                            step: 2)
                        Text("\(settings.teleprompterTextSize) pt")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                    .frame(width: 260)
                } label: {
                    SettingsRowTitle(.teleprompterAppearance, "Text size")
                }
                Picker(selection: $settings.teleprompterHighlight) {
                    ForEach(TeleprompterHighlight.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.teleprompterAppearance, "Highlight color")
                }
            } header: {
                SettingsSectionHeader(.teleprompterAppearance)
            }
            .settingsEnabled(settings.teleprompterEnabled)

            FeatureCommandsSection(owner: .teleprompter, anchor: .teleprompterCommands)
                .settingsEnabled(settings.teleprompterEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.teleprompter)
    }

    private var modeDetail: String {
        switch settings.teleprompterMode {
        case .wordTracking: "Highlights each word as you say it, using speech recognition."
        case .classic: "Scrolls at a steady speed. No microphone."
        case .voiceActivated: "Scrolls while you speak and waits while you pause."
        }
    }
}
