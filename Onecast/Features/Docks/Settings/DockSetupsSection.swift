import SwiftUI

/// Setups: the docks shown, their layouts and the macOS Dock's layout, switched in one go.
struct DockSetupsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store
    @State private var editedSetupID: UUID?

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        let configuration = store.configuration
        Section {
            if configuration.setups.isEmpty {
                Text("A setup remembers what is on screen now, so one shortcut can bring it back.")
                    .foregroundStyle(.secondary)
            }

            ForEach(configuration.setups) { setup in
                DockSetupRow(
                    setup: setup,
                    nativeLayoutName: configuration.nativeLayouts.first {
                        $0.id == setup.nativeLayoutID
                    }?.name,
                    isActive: setup.id == configuration.activeSetupID,
                    isEdited: setup.id == editedSetupID,
                    onEdit: { editedSetupID = editedSetupID == setup.id ? nil : setup.id })
                if setup.id == editedSetupID {
                    DockSetupEditor(setupID: setup.id)
                }
            }

            Button {
                editedSetupID = coordinator.addSetup().id
            } label: {
                SettingsRowTitle(.docksSetups, "Add Setup")
            }
        } header: {
            SettingsSectionHeader(.docksSetups)
        } footer: {
            Text("Add Setup records which docks are shown, each one's layout and the macOS Dock's.")
        }
    }
}

private struct DockSetupRow: View {
    let setup: DockSetup
    let nativeLayoutName: String?
    let isActive: Bool
    let isEdited: Bool
    let onEdit: () -> Void

    @Environment(AppCore.self) private var core
    @Environment(HotKeyManager.self) private var hotKeys

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        SettingsRow(title: setup.name, subtitle: summary) {
            ColorDot(color: setup.color.swatch)
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            ShortcutRecorder(action: .dockSetup(setup.id))

            if isActive {
                Label("Active", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Button("Activate") { coordinator.activateSetup(id: setup.id) }
                    .accessibilityLabel("Activate \(setup.name)")
            }

            DockIconButton(
                symbol: isEdited ? "pencil.circle.fill" : "pencil",
                label: isEdited ? "Close the editor for \(setup.name)" : "Edit \(setup.name)",
                isHighlighted: isEdited, action: onEdit)

            DockIconButton(
                symbol: "trash", label: "Delete \(setup.name)", isDestructive: true,
                action: delete)
        }
    }

    private var summary: String {
        let docks = setup.docks.count == 1 ? "1 dock" : "\(setup.docks.count) docks"
        return "\(nativeLayoutName ?? "macOS Dock unchanged") · \(docks)"
    }

    private func delete() {
        Task {
            let confirmed = await core.confirm(
                title: "Delete “\(setup.name)”?", message: "Its shortcut goes with it.",
                symbol: "trash", confirmTitle: "Delete")
            guard confirmed else { return }
            hotKeys.setBinding(nil, for: .dockSetup(setup.id))
            coordinator.removeSetup(id: setup.id)
        }
    }
}

/// What activating a setup does to one dock.
private enum DockSetupChoice: CaseIterable {
    case unchanged, shown, hidden

    var title: String {
        switch self {
        case .unchanged: "Leave as is"
        case .shown: "Show"
        case .hidden: "Hide"
        }
    }

    init(_ state: DockSetup.DockState?) {
        guard let state else {
            self = .unchanged
            return
        }
        self = state.isVisible ? .shown : .hidden
    }
}

/// One setup's name, colour, macOS Dock layout and what it does to each dock.
private struct DockSetupEditor: View {
    let setupID: UUID

    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        if let setup = store.setup(id: setupID) {
            Group {
                LabeledContent("Name") {
                    DockTextField(
                        value: setup.name, prompt: "Setup name", accessibilityName: "Setup name",
                        commit: { name in edit { $0.name = name } })
                }

                LabeledContent("Colour") {
                    DockColorSwatches(selection: setup.color) { color in
                        if let color { edit { $0.color = color } }
                    }
                }

                Picker(
                    selection: Binding(
                        get: { setup.nativeLayoutID },
                        set: { id in edit { $0.nativeLayoutID = id } })
                ) {
                    Text("Leave as is").tag(UUID?.none)
                    ForEach(store.configuration.nativeLayouts) { layout in
                        Text(layout.name).tag(UUID?.some(layout.id))
                    }
                } label: {
                    Text("macOS Dock layout")
                    Text("Applied to the macOS Dock when the setup is activated.")
                }

                ForEach(store.docks) { dock in
                    dockRow(dock, in: setup)
                }
            }
        }
    }

    private func dockRow(_ dock: CustomDock, in setup: DockSetup) -> some View {
        let state = setup.docks.first { $0.dockID == dock.id }
        let choice = DockSetupChoice(state)
        return LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                Picker(
                    "What the setup does to \(dock.name)",
                    selection: Binding(
                        get: { choice },
                        set: { choice in setChoice(choice, for: dock) })
                ) {
                    ForEach(DockSetupChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Picker(
                    "Layout of \(dock.name)",
                    selection: Binding(
                        get: { state?.layoutID },
                        set: { id in setLayout(id, for: dock) })
                ) {
                    Text("Keep current layout").tag(UUID?.none)
                    ForEach(dock.layouts) { layout in
                        Text(layout.name).tag(UUID?.some(layout.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .settingsEnabled(choice != .unchanged)
            }
        } label: {
            Text(dock.name)
        }
    }

    private func edit(_ change: (inout DockSetup) -> Void) {
        guard var setup = store.setup(id: setupID) else { return }
        change(&setup)
        coordinator.updateSetup(setup)
    }

    private func setChoice(_ choice: DockSetupChoice, for dock: CustomDock) {
        edit { setup in
            let index = setup.docks.firstIndex { $0.dockID == dock.id }
            switch (choice, index) {
            case (.unchanged, let index?): setup.docks.remove(at: index)
            case (.unchanged, nil): break
            case (_, let index?): setup.docks[index].isVisible = choice == .shown
            case (_, nil):
                setup.docks.append(
                    DockSetup.DockState(dockID: dock.id, isVisible: choice == .shown, layoutID: nil))
            }
        }
    }

    private func setLayout(_ layoutID: UUID?, for dock: CustomDock) {
        edit { setup in
            guard let index = setup.docks.firstIndex(where: { $0.dockID == dock.id }) else { return }
            setup.docks[index].layoutID = layoutID
        }
    }
}
