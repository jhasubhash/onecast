import SwiftUI

/// Saved arrangements of the macOS Dock's pinned apps, applied on demand or by a setup.
struct NativeDockLayoutsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store
    @State private var newName = ""

    private var coordinator: DockCoordinator { core.dockCoordinator }
    private var trimmedName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let configuration = store.configuration
        Section {
            Toggle(
                isOn: Binding(
                    get: { configuration.savesNativeDockChanges },
                    set: { coordinator.setSavesNativeDockChanges($0) })
            ) {
                SettingsRowTitle(.docksNativeLayouts, "Automatically save Dock changes")
                Text("Changes made in the macOS Dock go into the layout applied last.")
            }

            LabeledContent {
                HStack(spacing: Theme.Spacing.md) {
                    TextField("", text: $newName, prompt: Text("Layout name"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: DockSettingsMetrics.nameFieldWidth)
                        .onSubmit(create)
                        .accessibilityLabel("Name for the new layout")
                    Button("Create", action: create)
                        .settingsEnabled(!trimmedName.isEmpty)
                }
            } label: {
                SettingsRowTitle(.docksNativeLayouts, "Create from Current Dock")
                Text("Saves the macOS Dock's pinned apps and spacers as they are now.")
            }

            if configuration.nativeLayouts.isEmpty {
                Text("No saved layouts yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(configuration.nativeLayouts) { layout in
                    NativeDockLayoutRow(
                        layout: layout, isActive: layout.id == configuration.activeNativeLayoutID)
                }
            }
        } header: {
            SettingsSectionHeader(.docksNativeLayouts)
        } footer: {
            Text("Only pinned apps and spacers are saved; folders, files and recent items are not.")
        }
    }

    private func create() {
        guard !trimmedName.isEmpty, coordinator.captureNativeLayout(name: trimmedName) != nil
        else { return }
        newName = ""
    }
}

private struct NativeDockLayoutRow: View {
    let layout: NativeDockLayout
    let isActive: Bool

    @Environment(AppCore.self) private var core

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                DockColorMenuButton(color: layout.color, name: layout.name) { color in
                    var updated = layout
                    updated.color = color
                    coordinator.updateNativeLayout(updated)
                }
                DockTextField(
                    value: layout.name, prompt: "Layout name", accessibilityName: "Layout name",
                    commit: { name in
                        var updated = layout
                        updated.name = name
                        coordinator.updateNativeLayout(updated)
                    })
                Spacer(minLength: Theme.Spacing.lg)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                        .help("Applied last")
                        .accessibilityLabel("Applied last")
                }
                Button("Apply") { coordinator.applyNativeLayout(id: layout.id) }
                    .accessibilityLabel("Apply \(layout.name) to the macOS Dock")
                DockIconButton(
                    symbol: "arrow.triangle.2.circlepath",
                    label: "Replace \(layout.name) with the current Dock…",
                    action: { coordinator.replaceNativeLayoutWithCurrent(id: layout.id) })
                DockIconButton(
                    symbol: "trash", label: "Delete \(layout.name)", isDestructive: true,
                    action: delete)
            }
            NativeTileStrip(layout: layout)
        }
    }

    private func delete() {
        Task {
            let confirmed = await core.confirm(
                title: "Delete “\(layout.name)”?",
                message: "Setups that use it leave the macOS Dock as it is.", symbol: "trash",
                confirmTitle: "Delete")
            if confirmed { coordinator.removeNativeLayout(id: layout.id) }
        }
    }
}

/// A saved layout's tiles in order: "+" between two adds a spacer, ✕ on one removes it.
private struct NativeTileStrip: View {
    let layout: NativeDockLayout

    @Environment(AppCore.self) private var core

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(0...layout.tiles.count, id: \.self) { index in
                    NativeInsertSlot { insertSpacer(at: index) }
                    if index < layout.tiles.count {
                        NativeTileView(tile: layout.tiles[index]) { remove(at: index) }
                    }
                }
            }
            .padding(DockSettingsMetrics.stripInset)
        }
        .scrollIndicators(.automatic)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tiles of \(layout.name)")
    }

    private func insertSpacer(at index: Int) {
        var updated = layout
        updated.tiles.insert(NativeDockTile(kind: .spacer(.small), raw: nil), at: index)
        core.dockCoordinator.updateNativeLayout(updated)
    }

    private func remove(at index: Int) {
        guard layout.tiles.indices.contains(index) else { return }
        var updated = layout
        updated.tiles.remove(at: index)
        core.dockCoordinator.updateNativeLayout(updated)
    }
}

private struct NativeInsertSlot: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(hovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                .frame(width: DockSettingsMetrics.nativeSlot, height: DockSettingsMetrics.nativeTile)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Add a spacer here")
        .accessibilityLabel("Add a spacer here")
    }
}

private struct NativeTileView: View {
    let tile: NativeDockTile
    let onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        content
            .frame(width: width, height: DockSettingsMetrics.nativeTile)
            .overlay(alignment: .topTrailing) {
                if hovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .background(Circle().fill(Theme.Colors.controlSurface))
                    }
                    .buttonStyle(.plain)
                    .offset(x: Theme.Spacing.xs, y: -Theme.Spacing.xs)
                    .accessibilityLabel("Remove \(title)")
                }
            }
            .onHover { hovered = $0 }
            .help(title)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityAction(named: "Remove", onRemove)
    }

    @ViewBuilder
    private var content: some View {
        switch tile.kind {
        case .app(let bundleID, let path, _):
            DockFileIcon(path: path, bundleID: bundleID, size: DockSettingsMetrics.nativeTile)
        case .spacer:
            RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                .strokeBorder(Theme.Colors.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        case .other:
            DockSymbolTile(name: "questionmark.square.dashed", size: DockSettingsMetrics.nativeTile)
        }
    }

    private var width: CGFloat {
        guard case .spacer(.small) = tile.kind else { return DockSettingsMetrics.nativeTile }
        return DockSettingsMetrics.nativeTile / 2
    }

    private var title: String {
        switch tile.kind {
        case .app(_, _, let label): label
        case .spacer(let size): size.settingsTitle
        case .other(let type): "Unsupported tile (\(type))"
        }
    }
}
