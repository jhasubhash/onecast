import SwiftUI

/// Settings ▸ Fallbacks: which commands a typed query is offered to, and in what order.
struct FallbacksSettingsView: View {
    @Environment(AppCore.self) private var core
    /// Observed so a reorder or a checkbox redraws the list under the button that moved it.
    @Environment(FallbackStore.self) private var store

    private var fallbacks: [Fallback] { core.fallbackCoordinator.available }

    var body: some View {
        Form {
            Section {
                Text(
                    "Every search offers these below its results, under “Use … with”. "
                        + "Each one takes what you typed as its input."
                )
                .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(.fallbacksFallbacks)
            }

            Section {
                let fallbacks = fallbacks
                if fallbacks.isEmpty {
                    Text("Nothing to offer — the features these belong to are switched off.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // One row holding a lazy stack: a `Form` realizes every row it is handed.
                    LazyVStack(spacing: 0) {
                        ForEach(Array(fallbacks.enumerated()), id: \.element) { index, fallback in
                            if index > 0 { Divider() }
                            FallbackRow(fallback: fallback, order: fallbacks, index: index)
                                .padding(.vertical, Self.rowPadding)
                        }
                    }
                    .padding(.vertical, -Self.rowPadding)
                }
            } footer: {
                Text(
                    "A quicklink appears here once its link contains an {argument}, "
                        + "which the query fills in. Give one trigger words to float it to the top "
                        + "whenever your search contains one of them."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.fallbacks)
        .releasesFocusOnOutsideClick()
    }

    /// A grouped `Form` row's own vertical padding.
    private static let rowPadding: CGFloat = 15
}

private struct FallbackRow: View {
    let fallback: Fallback
    /// The visible order, so a move stores every id rather than only the two that swapped.
    let order: [Fallback]
    let index: Int

    @Environment(AppCore.self) private var core
    @Environment(FallbackStore.self) private var store

    var body: some View {
        if let entry = core.fallbackCoordinator.entry(for: fallback) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SettingsRow(title: entry.name, subtitle: entry.kindLabel) {
                    AppIconView(app: entry)
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                } trailing: {
                    Button {
                        move(by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(entry.name) up")
                    Button {
                        move(by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == order.count - 1)
                    .accessibilityLabel("Move \(entry.name) down")
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Offer \(entry.name) as a fallback")
                }
                if case .quicklink(let id) = fallback {
                    FallbackTriggersField(quicklinkID: id, name: entry.name)
                        .padding(.leading, Theme.Size.settingsRowIcon + Theme.Spacing.lg)
                }
            }
        }
    }

    private func move(by delta: Int) {
        guard order.indices.contains(index + delta) else { return }
        store.exchange(fallback, with: order[index + delta], in: order)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(fallback) },
            set: { store.setEnabled($0, for: fallback) }
        )
    }
}

/// The per-quicklink trigger editor under a fallback row: comma-separated words that float the
/// quicklink to the top of the list whenever the typed query contains one. Dressed like `AliasField`.
private struct FallbackTriggersField: View {
    let quicklinkID: UUID
    let name: String
    @Environment(AppCore.self) private var core
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        let placeholder = Text("Trigger words, comma-separated")
            .foregroundStyle(Theme.Colors.textSecondary)
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "arrow.up.to.line.compact")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("", text: $draft, prompt: placeholder)
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(Theme.Typography.keyCap)
                .focused($focused)
                // The system ring insets the field editor on focus, hopping the placeholder left.
                .focusEffectDisabled()
                .onSubmit(commit)
                .onExitCommand(perform: revert)
                // The pane's `releasesFocusOnOutsideClick` resigns; this catches it landing.
                .onChange(of: focused) { _, now in
                    if !now { commit() }
                }
            if !draft.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear trigger words for \(name)")
            }
        }
        .onAppear { draft = stored.joined(separator: ", ") }
        // A backup import or an edit elsewhere replaces the record out from under an unfocused row.
        .onChange(of: stored) { _, now in
            if !focused { draft = now.joined(separator: ", ") }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(height: 24)
        .background(shape.fill(Theme.Colors.cardFill))
        .overlay(
            shape.strokeBorder(
                focused ? Color.accentColor : Theme.Colors.cardStroke, lineWidth: 1)
        )
        .clipShape(shape)
        .accessibilityLabel("Trigger words for \(name)")
    }

    private var stored: [String] { core.quicklinks.quicklink(id: quicklinkID)?.triggers ?? [] }

    /// The one commit path — ↵ or focus landing elsewhere; the store normalises what it is handed.
    private func commit() {
        try? core.quicklinks.setTriggers(draft.split(separator: ",").map(String.init), id: quicklinkID)
        draft = stored.joined(separator: ", ")
    }

    private func revert() {
        draft = stored.joined(separator: ", ")
        focused = false
    }

    private func clear() {
        draft = ""
        commit()
    }
}
