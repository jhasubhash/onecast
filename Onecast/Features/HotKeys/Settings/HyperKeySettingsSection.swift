import SwiftUI

struct HyperKeySettingsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var diagnostics: HyperKeyDiagnostics?
    @State private var takeover: HyperKeyDiagnostics.Takeover?

    private var manager: HyperKeyManager { core.hyperKey }

    /// The Hyper modifier chord as prose glyphs, tracking the Include Shift toggle.
    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    /// Only a choice made here resets Quick Press: settings.json may set both keys at once.
    private var hyperKeySelection: Binding<HyperKeyPhysicalKey> {
        Binding(
            get: { settings.hyperKey },
            set: { key in
                guard key != settings.hyperKey else { return }
                settings.hyperKey = key
                // A Quick Press choice is meaningless for a different key.
                settings.hyperKeyQuickPress = .none
                if key != .none { Permissions.ensureAccessibility() }
            })
    }

    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else {
            return
                "Select a physical key to remap to the \(hyperGlyphs) modifier keys simultaneously."
        }
        return
            "Pressing \(settings.hyperKey.title) will trigger the left \(hyperGlyphs) modifier keys."
            + " Hyper Key shortcuts are shown in Onecast with ✦."
    }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker(selection: hyperKeySelection) {
                ForEach(HyperKeyPhysicalKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            } label: {
                SettingsRowTitle(.generalHyperKey, "Hyper Key")
                Text(hyperSubtitle)
            }

            if settings.hyperKey != .none {
                HyperKeyStatusRow(
                    status: manager.status, takeover: takeover, isShowingDiagnostics: diagnostics != nil
                ) {
                    diagnostics = diagnostics == nil ? manager.diagnostics() : nil
                    takeover = manager.takeover()
                }
            }

            if settings.hyperKey.hasOriginalFunction {
                Picker(selection: $settings.hyperKeyQuickPress) {
                    Text("Does Nothing").tag(HyperKeyQuickPress.none)
                    if let original = settings.hyperKey.quickPressOriginalTitle {
                        Text(original).tag(HyperKeyQuickPress.originalKey)
                    }
                    Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                } label: {
                    SettingsRowTitle(.generalHyperKey, "Quick Press")
                    Text(
                        "Select an action to perform when \(settings.hyperKey.title) is pressed without any other keys."
                    )
                }
            }

            Toggle(isOn: $settings.hyperKeyIncludesShift) {
                SettingsRowTitle(.generalHyperKey, "Include Shift (⇧)")
                Text("Hyper Key will remap to the \(hyperGlyphs) modifier keys.")
            }
            // Flipping it re-points recorded chords, so it needs a chord to mean.
            .settingsEnabled(settings.hyperKey != .none)

            if settings.hyperKey.supportsSecureInputCompatibility {
                Toggle(isOn: $settings.hyperKeySecureInputCompatibility) {
                    SettingsRowTitle(.generalHyperKey, "Secure Input Compatibility")
                    Text(
                        "Onecast's Hyper shortcuts also work in password fields and secure terminals, "
                            + "where Right Control (⌃) with the same key triggers them. "
                            + "While on, Right Control (⌃) acts as the Hyper Key too.")
                }
            }
        } header: {
            SettingsSectionHeader(.generalHyperKey)
        }
        .onAppear { takeover = manager.takeover() }
        .onChange(of: manager.status) {
            takeover = manager.takeover()
            if diagnostics != nil { diagnostics = manager.diagnostics() }
        }

        if let diagnostics, settings.hyperKey != .none {
            HyperKeyDiagnosticsSection(
                diagnostics: diagnostics,
                refresh: {
                    self.diagnostics = manager.diagnostics()
                    takeover = self.diagnostics?.takeover
                },
                restart: {
                    manager.restart()
                    self.diagnostics = manager.diagnostics()
                    takeover = self.diagnostics?.takeover
                })
        }
    }

    private struct HyperKeyStatusRow: View {
        let status: HyperKeyManager.Status
        let takeover: HyperKeyDiagnostics.Takeover?
        let isShowingDiagnostics: Bool
        let toggleDiagnostics: () -> Void

        var body: some View {
            SettingsRow(title: "Status", subtitle: detail, subtitleLineLimit: 3) {
                HStack(spacing: Theme.Spacing.sm) {
                    ColorDot(color: tint)
                    Text(title).foregroundStyle(.secondary)
                    if status == .needsAccessibility {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    }
                    Button(
                        isShowingDiagnostics ? "Hide Diagnostics" : "Diagnostics…", action: toggleDiagnostics)
                }
            }
        }

        private var title: String {
            if takeover != nil { return "Taken Over" }
            switch status {
            case .off: return "Off"
            case .active: return "Active"
            case .needsAccessibility: return "Needs Accessibility"
            case .blocked: return "Blocked"
            case .remapUnavailable: return "Unavailable"
            case .paused: return "Paused"
            }
        }

        private var detail: String? {
            if let takeover { return describe(takeover) }
            switch status {
            case .blocked(let appName): return "\(appName) runs its own Hyper Key. Quit it to use this one."
            case .remapUnavailable: return "macOS refused to remap the keyboard."
            case .paused: return "Handed back while the Mac sleeps, locks or switches user."
            case .off, .active, .needsAccessibility: return nil
            }
        }

        private var tint: Color {
            if takeover != nil { return Theme.Colors.destructive }
            switch status {
            case .active: return Theme.Colors.success
            case .needsAccessibility, .paused: return Theme.Colors.warning
            case .off, .blocked, .remapUnavailable: return Theme.Colors.destructive
            }
        }

        private func describe(_ takeover: HyperKeyDiagnostics.Takeover) -> String {
            let keyboards = takeover.keyboards.formatted(.list(type: .and))
            var sentences = ["Another app now remaps Caps Lock on \(keyboards)."]
            if !takeover.likelyApps.isEmpty {
                sentences.append(
                    "Probably \(takeover.likelyApps.formatted(.list(type: .or))).")
            }
            return sentences.joined(separator: " ")
        }
    }
}
