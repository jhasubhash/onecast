import Combine
import SwiftUI

/// "Placement · Work": the editor's sections each say which dock they are editing.
private struct DockEditorHeader: View {
    let anchor: SettingsAnchor
    let dock: CustomDock

    var body: some View {
        SettingsSectionHeader(anchor: anchor) {
            Text("\(anchor.title) · \(dock.name)")
        }
    }
}

/// A value and the stepper that moves it, the trailing half of a numeric row.
private struct DockStepper: View {
    let name: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("\(value) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper(name, value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}

// MARK: - Placement

struct DockPlacementSection: View {
    let dockID: UUID
    let displays: [DockDisplayOption]

    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        if let dock = store.dock(id: dockID) {
            Section {
                LabeledContent {
                    DockTextField(
                        value: dock.name, prompt: "Dock", accessibilityName: "Dock name",
                        commit: { coordinator.renameDock(id: dock.id, to: $0) })
                } label: {
                    SettingsRowTitle(.docksPlacement, "Name")
                }

                Picker(selection: displayBinding(dock)) {
                    Text("Main display").tag(String?.none)
                    ForEach(displays) { display in
                        Text(display.name).tag(String?.some(display.key))
                    }
                    if let key = dock.placement.displayKey,
                        !displays.contains(where: { $0.key == key })
                    {
                        Text("Disconnected display").tag(String?.some(key))
                    }
                } label: {
                    SettingsRowTitle(.docksPlacement, "Display")
                    Text("Main display follows the one that holds the menu bar.")
                }

                Picker(selection: edgeBinding(dock)) {
                    ForEach(DockEdge.settingsOrder, id: \.self) { edge in
                        Text(edge.settingsTitle).tag(edge)
                    }
                } label: {
                    SettingsRowTitle(.docksPlacement, "Edge")
                }

                LabeledContent {
                    HStack(spacing: Theme.Spacing.md) {
                        alignmentPresets(dock)
                        DockStepper(
                            name: "Position along edge", value: percentBinding(dock),
                            range: 0...100, step: 5, unit: "%")
                    }
                } label: {
                    SettingsRowTitle(.docksPlacement, "Position along edge")
                    Text("Where the dock's centre sits; 0% is the start of the edge.")
                }
            } header: {
                DockEditorHeader(anchor: .docksPlacement, dock: dock)
            }
        }
    }

    private func percentBinding(_ dock: CustomDock) -> Binding<Int> {
        Binding(
            get: { Int((dock.placement.alignment * 100).rounded()) },
            set: { value in
                coordinator.updatePlacement(dockID: dock.id) { $0.alignment = Double(value) / 100 }
            })
    }

    private func displayBinding(_ dock: CustomDock) -> Binding<String?> {
        Binding(
            get: { dock.placement.displayKey },
            set: { key in coordinator.updatePlacement(dockID: dock.id) { $0.displayKey = key } })
    }

    private func edgeBinding(_ dock: CustomDock) -> Binding<DockEdge> {
        Binding(
            get: { dock.placement.edge },
            set: { edge in coordinator.updatePlacement(dockID: dock.id) { $0.edge = edge } })
    }

    /// Keyed on the edge, because the segmented control names its segments once, when it is made.
    private func alignmentPresets(_ dock: CustomDock) -> some View {
        typealias Segmented = SteadySegmentedPicker<DockAlignmentPreset?>
        let edge = dock.placement.edge
        return Segmented(
            title: "Position preset",
            options: DockAlignmentPreset.allCases.map {
                Segmented.Option(value: $0, title: $0.title(on: edge))
            },
            selection: Binding(
                get: { DockAlignmentPreset(alignment: dock.placement.alignment) },
                set: { preset in
                    guard let preset else { return }
                    coordinator.updatePlacement(dockID: dock.id) { $0.alignment = preset.alignment }
                })
        )
        .id(edge)
    }
}

// MARK: - Appearance

struct DockAppearanceSection: View {
    let dockID: UUID

    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store

    private var coordinator: DockCoordinator { core.dockCoordinator }

    private static let sizeStep = 4

    var body: some View {
        if let dock = store.dock(id: dockID) {
            let appearance = dock.appearance
            Section {
                Picker(selection: appearanceBinding(dock, \.material)) {
                    ForEach(DockMaterial.allCases, id: \.self) { material in
                        Text(material.settingsTitle).tag(material)
                    }
                } label: {
                    SettingsRowTitle(.docksAppearance, "Material")
                }

                LabeledContent {
                    DockStepper(
                        name: "Tile size", value: tileSizeBinding(dock),
                        range: Int(DockAppearance.tileSizeRange.lowerBound)...Int(
                            DockAppearance.tileSizeRange.upperBound),
                        step: Self.sizeStep, unit: "pt")
                } label: {
                    SettingsRowTitle(.docksAppearance, "Tile size")
                }

                Toggle(isOn: magnificationBinding(dock)) {
                    SettingsRowTitle(.docksAppearance, "Magnification")
                    Text("Enlarges the tile under the pointer, as the macOS Dock does.")
                }

                if appearance.magnifies {
                    LabeledContent {
                        DockStepper(
                            name: "Magnified size", value: magnifiedSizeBinding(dock),
                            range: (Int(appearance.tileSize) + Self.sizeStep)...Int(
                                DockAppearance.magnifiedSizeRange.upperBound),
                            step: Self.sizeStep, unit: "pt")
                    } label: {
                        SettingsRowTitle(.docksAppearance, "Magnified size")
                    }
                }

                Toggle(isOn: appearanceBinding(dock, \.autoHides)) {
                    SettingsRowTitle(.docksAppearance, "Auto-hide")
                    Text("Slides off the edge until the pointer reaches it.")
                }

                Toggle(isOn: appearanceBinding(dock, \.showsHandleWhenHidden)) {
                    SettingsRowTitle(.docksAppearance, "Show handle when hidden")
                    Text("Leaves a thin strip showing where the dock is.")
                }
                .settingsEnabled(appearance.autoHides)

                Picker(selection: appearanceBinding(dock, \.layer)) {
                    ForEach(DockLayer.allCases, id: \.self) { layer in
                        Text(layer.settingsTitle).tag(layer)
                    }
                } label: {
                    SettingsRowTitle(.docksAppearance, "Layer")
                }

                Toggle(isOn: appearanceBinding(dock, \.hidesWhenMacOSDockAppears)) {
                    SettingsRowTitle(.docksAppearance, "Hide when macOS Dock appears")
                    Text("Steps aside while the macOS Dock is showing on the same edge.")
                }

                Toggle(isOn: appearanceBinding(dock, \.showsWidgetLabels)) {
                    SettingsRowTitle(.docksAppearance, "Show widget labels")
                    Text("Names a widget above it on hover. Labels on its own buttons show either way.")
                }
            } header: {
                DockEditorHeader(anchor: .docksAppearance, dock: dock)
            }
        }
    }

    private func appearanceBinding<Value>(
        _ dock: CustomDock, _ keyPath: WritableKeyPath<DockAppearance, Value>
    ) -> Binding<Value> {
        Binding(
            get: { dock.appearance[keyPath: keyPath] },
            set: { value in
                coordinator.updateAppearance(dockID: dock.id) { $0[keyPath: keyPath] = value }
            })
    }

    private func tileSizeBinding(_ dock: CustomDock) -> Binding<Int> {
        Binding(
            get: { Int(dock.appearance.tileSize.rounded()) },
            set: { size in
                coordinator.updateAppearance(dockID: dock.id) { appearance in
                    let reach = appearance.magnifiedSize - appearance.tileSize
                    let magnifies = appearance.magnifies
                    appearance.tileSize = Double(size)
                    appearance.magnifiedSize = magnifies ? Double(size) + reach : Double(size)
                }
            })
    }

    private func magnifiedSizeBinding(_ dock: CustomDock) -> Binding<Int> {
        Binding(
            get: { Int(dock.appearance.magnifiedSize.rounded()) },
            set: { size in
                coordinator.updateAppearance(dockID: dock.id) { $0.magnifiedSize = Double(size) }
            })
    }

    private func magnificationBinding(_ dock: CustomDock) -> Binding<Bool> {
        Binding(
            get: { dock.appearance.magnifies },
            set: { isOn in
                coordinator.updateAppearance(dockID: dock.id) { appearance in
                    guard isOn else {
                        appearance.magnifiedSize = appearance.tileSize
                        return
                    }
                    let grown = (appearance.tileSize * 1.5 / Double(Self.sizeStep)).rounded()
                        * Double(Self.sizeStep)
                    appearance.magnifiedSize = max(grown, appearance.tileSize + Double(Self.sizeStep))
                }
            })
    }
}

// MARK: - Content

struct DockContentSection: View {
    let dockID: UUID

    @Environment(AppCore.self) private var core
    @Environment(DockStore.self) private var store
    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var coordinator: DockCoordinator { core.dockCoordinator }

    var body: some View {
        if let dock = store.dock(id: dockID) {
            let content = dock.content
            Section {
                Toggle(isOn: contentBinding(dock, \.showsRunningApps)) {
                    SettingsRowTitle(.docksContent, "Show running apps")
                    Text("Apps that are open but not pinned, after a divider.")
                }
                .onReceive(refreshTimer) { _ in
                    isTrusted = Permissions.isAccessibilityTrusted()
                }

                Toggle(isOn: contentBinding(dock, \.showsMinimizedWindows)) {
                    SettingsRowTitle(.docksContent, "Show minimized windows")
                    Text("Needs the Accessibility permission.")
                }

                Toggle(isOn: contentBinding(dock, \.showsTrash)) {
                    SettingsRowTitle(.docksContent, "Show Trash")
                }

                Toggle(isOn: contentBinding(dock, \.clickFocusedAppMinimizes)) {
                    SettingsRowTitle(.docksContent, "Click focused app to minimize")
                    Text("Needs the Accessibility permission.")
                }

                Toggle(isOn: contentBinding(dock, \.showsBadges)) {
                    SettingsRowTitle(.docksContent, "Show app badges")
                    Text("Needs the Accessibility permission.")
                }

                if needsAccessibility(content), !isTrusted {
                    HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(width: Theme.Size.settingsRowIcon)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("Accessibility permission required")
                                .foregroundStyle(.orange)
                            Text("Onecast can't see other apps' windows or badges until it is granted.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Theme.Spacing.lg)
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    }
                }
            } header: {
                DockEditorHeader(anchor: .docksContent, dock: dock)
            }
        }
    }

    private func needsAccessibility(_ content: DockContentOptions) -> Bool {
        content.showsMinimizedWindows || content.showsBadges || content.clickFocusedAppMinimizes
    }

    private func contentBinding(
        _ dock: CustomDock, _ keyPath: WritableKeyPath<DockContentOptions, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { dock.content[keyPath: keyPath] },
            set: { value in
                coordinator.updateContent(dockID: dock.id) { $0[keyPath: keyPath] = value }
            })
    }
}
