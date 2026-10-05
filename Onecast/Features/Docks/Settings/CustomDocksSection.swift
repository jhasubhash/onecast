import SwiftUI

/// Every custom dock: shown or hidden, edited, copied or removed from one row each.
struct CustomDocksSection: View {
    let displays: [DockDisplayOption]
    let editedDockID: UUID?
    let onEdit: (UUID) -> Void

    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store

    var body: some View {
        Section {
            if store.docks.isEmpty {
                Text("No custom docks yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.docks) { dock in
                    CustomDockRow(
                        dock: dock, displays: displays, isEdited: dock.id == editedDockID,
                        onEdit: { onEdit(dock.id) })
                }
            }

            Button {
                onEdit(core.dockCoordinator.addDock().id)
            } label: {
                SettingsRowTitle(.docksCustomDocks, "Add Dock")
            }
        } header: {
            SettingsSectionHeader(.docksCustomDocks)
        } footer: {
            if store.configuration.nativeMode == .macOSOnly {
                Text("Custom docks stay off while the setup is “macOS Dock only”.")
            }
        }
    }
}

private struct CustomDockRow: View {
    let dock: CustomDock
    let displays: [DockDisplayOption]
    let isEdited: Bool
    let onEdit: () -> Void

    @Environment(AppCore.self) private var core

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        SettingsRow(title: dock.name, subtitle: summary) {
            SymbolImage(name: dock.placement.edge.settingsSymbol, size: 13)
        } trailing: {
            ShortcutRecorder(action: .dockVisibility(dock.id))

            Toggle(
                "",
                isOn: Binding(
                    get: { dock.isVisible },
                    set: { coordinator.setDockVisible(id: dock.id, $0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Show this dock")
            .accessibilityLabel("Show \(dock.name)")

            DockIconButton(
                symbol: isEdited ? "pencil.circle.fill" : "pencil",
                label: isEdited ? "Editing \(dock.name)" : "Edit \(dock.name)",
                isHighlighted: isEdited, action: onEdit)

            DockIconButton(
                symbol: "plus.square.on.square", label: "Duplicate \(dock.name)",
                action: { coordinator.duplicateDock(id: dock.id) })

            DockIconButton(
                symbol: "trash", label: "Delete \(dock.name)", isDestructive: true,
                action: { coordinator.removeDock(id: dock.id) })
        }
    }

    private var summary: String {
        let display = DockDisplays.name(for: dock.placement.displayKey, in: displays)
        return "\(dock.placement.edge.settingsTitle) · \(display)"
    }
}
