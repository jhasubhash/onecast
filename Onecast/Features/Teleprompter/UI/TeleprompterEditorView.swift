import SwiftUI

/// Where a script is pasted or written, with the run's few choices beside the Start button.
struct TeleprompterEditorView: View {
    @Bindable var coordinator: TeleprompterCoordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $coordinator.draft)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.md)
                if coordinator.draft.isEmpty {
                    Text("Paste or write your script. Text in [square brackets] is a cue: shown, never read out.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.horizontal, Theme.Spacing.md + 5)
                        .padding(.vertical, Theme.Spacing.md)
                        .allowsHitTesting(false)
                }
            }
            .padding(.top, Theme.Size.noteTitlebar - Theme.Spacing.xl)
            Divider()
            HStack(spacing: Theme.Spacing.lg) {
                Picker("Mode", selection: $settings.teleprompterMode) {
                    ForEach(TeleprompterMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Picker("Position", selection: $settings.teleprompterPlacement) {
                    ForEach(TeleprompterPlacement.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                Text("\(TeleprompterScript(coordinator.draft).words.count) words")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button("Start", action: coordinator.startDraft)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
