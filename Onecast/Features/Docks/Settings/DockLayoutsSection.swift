import SwiftUI

/// A dock's layouts: which one it shows, and which one the items editor below is working on.
struct DockLayoutsSection: View {
    let dockID: UUID
    let editedLayoutID: UUID
    let onEdit: (UUID) -> Void

    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        if let dock = store.dock(id: dockID) {
            Section {
                ForEach(dock.layouts) { layout in
                    DockLayoutRow(
                        dockID: dock.id, layout: layout, isActive: layout.id == dock.activeLayoutID,
                        isEdited: layout.id == editedLayoutID, canDelete: dock.layouts.count > 1,
                        onEdit: { onEdit(layout.id) })
                }

                Button {
                    if let layout = coordinator.addLayout(dockID: dock.id) { onEdit(layout.id) }
                } label: {
                    SettingsRowTitle(.docksLayouts, "Add Layout")
                }
            } header: {
                SettingsSectionHeader(anchor: .docksLayouts) {
                    Text("\(SettingsAnchor.docksLayouts.title) · \(dock.name)")
                }
            } footer: {
                Text("A dock shows one layout at a time; swiping over it steps through them.")
            }
        }
    }
}

private struct DockLayoutRow: View {
    let dockID: UUID
    let layout: DockLayout
    let isActive: Bool
    let isEdited: Bool
    let canDelete: Bool
    let onEdit: () -> Void

    @Environment(AppCore.self) private var core

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                if isActive {
                    Label("Active", systemImage: "checkmark")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Use") {
                        coordinator.activateLayout(dockID: dockID, layoutID: layout.id)
                    }
                    .accessibilityLabel("Show \(layout.name) in the dock")
                }

                DockIconButton(
                    symbol: isEdited ? "pencil.circle.fill" : "pencil",
                    label: isEdited ? "Editing \(layout.name)" : "Edit items of \(layout.name)",
                    isHighlighted: isEdited, action: onEdit)

                DockIconButton(
                    symbol: "plus.square.on.square", label: "Duplicate \(layout.name)",
                    action: { coordinator.duplicateLayout(dockID: dockID, layoutID: layout.id) })

                DockIconButton(
                    symbol: "trash", label: "Delete \(layout.name)", isDestructive: true,
                    action: { coordinator.removeLayout(dockID: dockID, layoutID: layout.id) }
                )
                .settingsEnabled(canDelete)
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                DockColorMenuButton(color: layout.color, name: layout.name) { color in
                    coordinator.setLayoutColor(dockID: dockID, layoutID: layout.id, color)
                }
                DockTextField(
                    value: layout.name, prompt: "Layout name", accessibilityName: "Layout name",
                    commit: {
                        coordinator.renameLayout(dockID: dockID, layoutID: layout.id, to: $0)
                    })
            }
        }
    }
}
