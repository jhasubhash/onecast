import OnecastPluginKit
import SwiftUI

/// The selected item's own settings, shown as rows beneath the strip.
struct DockItemInspector: View {
    let dockID: UUID
    let layoutID: UUID
    let item: DockItem
    let index: Int
    let count: Int
    let onRemoved: () -> Void

    @Environment(AppCore.self) private var core

    private var coordinator: DockCoordinator { core.dockCoordinator }
    private var widgets: DockWidgetManager { coordinator.widgets }

    var body: some View {
        Group {
            header
            switch item.kind {
            case .app(let reference): locationRow(reference.path)
            case .file(let path): locationRow(path)
            case .folder(let reference): folderRows(reference)
            case .link(let reference): linkRows(reference)
            case .shortcut(let name): shortcutRow(name)
            case .spacer(let size): spacerRow(size)
            case .widget(let reference): widgetRows(reference)
            }
        }
    }

    private func save(_ kind: DockItem.Kind) {
        coordinator.updateItem(
            DockItem(id: item.id, kind: kind), dockID: dockID, layoutID: layoutID)
    }

    private func updateFolder(
        _ reference: DockFolderReference, _ change: (inout DockFolderReference) -> Void
    ) {
        var updated = reference
        change(&updated)
        save(.folder(updated))
    }

    private func updateLink(
        _ reference: DockLinkReference, _ change: (inout DockLinkReference) -> Void
    ) {
        var updated = reference
        change(&updated)
        save(.link(updated))
    }

    // MARK: - Header

    private var header: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                DockIconButton(
                    symbol: "chevron.left", label: "Move earlier",
                    action: {
                        coordinator.moveItem(
                            dockID: dockID, layoutID: layoutID, from: index, to: index - 1)
                    }
                )
                .settingsEnabled(index > 0)

                DockIconButton(
                    symbol: "chevron.right", label: "Move later",
                    action: {
                        coordinator.moveItem(
                            dockID: dockID, layoutID: layoutID, from: index, to: index + 2)
                    }
                )
                .settingsEnabled(index < count - 1)

                DockIconButton(
                    symbol: "trash", label: "Remove from this layout", isDestructive: true,
                    action: {
                        coordinator.removeItem(id: item.id, dockID: dockID, layoutID: layoutID)
                        onRemoved()
                    })
            }
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                DockItemGlyph(item: item, widgets: widgets, size: Theme.Size.rowIcon)
                    .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(DockItemPresentation.title(of: item, widgets: widgets))
                        .lineLimit(1)
                    Text(DockItemPresentation.kindName(of: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Apps, files, shortcuts and spacers

    private func locationRow(_ path: String) -> some View {
        LabeledContent("Location") {
            Text((path as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutRow(_ name: String) -> some View {
        LabeledContent("Shortcut") {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }

    private func spacerRow(_ size: DockSpacerSize) -> some View {
        Picker(
            "Size",
            selection: Binding(get: { size }, set: { save(.spacer($0)) })
        ) {
            ForEach(DockSpacerSize.allCases, id: \.self) { size in
                Text(size.settingsTitle).tag(size)
            }
        }
    }

    // MARK: - Folders

    @ViewBuilder
    private func folderRows(_ reference: DockFolderReference) -> some View {
        locationRow(reference.path)

        LabeledContent {
            DockTextField(
                value: reference.customName ?? "",
                prompt: DockItemPresentation.fileName(reference.path),
                accessibilityName: "Folder name in the dock", allowsEmpty: true,
                commit: { name in
                    updateFolder(reference) { $0.customName = name.isEmpty ? nil : name }
                })
        } label: {
            Text("Name")
            Text("Shown in the dock only; the folder keeps its own name.")
        }

        LabeledContent("Colour") {
            DockColorSwatches(selection: reference.color, allowsNone: true) { color in
                updateFolder(reference) { $0.color = color }
            }
        }

        LabeledContent("Letter") {
            DockTextField(
                value: reference.letter ?? "", prompt: "A",
                accessibilityName: "Letter drawn on the folder", allowsEmpty: true,
                characterLimit: 1, width: DockSettingsMetrics.letterFieldWidth,
                commit: { letter in
                    updateFolder(reference) { $0.letter = letter.isEmpty ? nil : letter }
                })
        }

        Toggle(
            "Show name",
            isOn: Binding(
                get: { reference.showsName },
                set: { shown in updateFolder(reference) { $0.showsName = shown } })
        )

        Button("Reset icon") {
            updateFolder(reference) {
                $0.color = nil
                $0.letter = nil
            }
        }
        .settingsEnabled(reference.color != nil || reference.letter != nil)
    }

    // MARK: - Links

    @ViewBuilder
    private func linkRows(_ reference: DockLinkReference) -> some View {
        LabeledContent("Title") {
            DockTextField(
                value: reference.title, prompt: "Title", accessibilityName: "Link title",
                commit: { title in updateLink(reference) { $0.title = title } })
        }

        LabeledContent("Address") {
            DockTextField(
                value: reference.url, prompt: "example.com", accessibilityName: "Link address",
                normalize: DockLinkInput.normalizedURL,
                commit: { address in updateLink(reference) { $0.url = address } })
        }

        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                DockTextField(
                    value: reference.symbol ?? "", prompt: "Website icon",
                    accessibilityName: "Link symbol", allowsEmpty: true,
                    commit: { name in
                        updateLink(reference) { $0.symbol = name.isEmpty ? nil : name }
                    })
                DockSymbolTile(name: DockItemGlyph.linkSymbol(reference), size: Theme.Size.rowIcon)
            }
        } label: {
            Text("Symbol")
            if let symbol = reference.symbol, !DockLinkInput.isSymbol(symbol) {
                Text("Not an SF Symbol, so the website's icon is used.")
                    .foregroundStyle(.orange)
            } else {
                Text("An SF Symbol name; blank uses the website's icon.")
            }
        }
    }

    // MARK: - Widgets

    @ViewBuilder
    private func widgetRows(_ reference: DockWidgetReference) -> some View {
        if let descriptor = widgets.descriptor(id: reference.widgetID) {
            let spans = Self.spans(of: descriptor, including: reference.span)
            Picker(
                "Size",
                selection: Binding(
                    get: { reference.span },
                    set: { span in
                        var updated = reference
                        updated.span = span
                        save(.widget(updated))
                    })
            ) {
                ForEach(spans, id: \.self) { span in
                    Text("\(span.settingsTitle) · \(span.settingsDetail)").tag(span)
                }
            }
            .settingsEnabled(spans.count > 1)

            DockWidgetPreferencesEditor(instanceID: item.id, widgetID: reference.widgetID)
        } else {
            Text("This widget isn't installed. Remove it, or install it again to bring it back.")
                .foregroundStyle(.secondary)
        }
    }

    /// Only the sizes the widget draws well at, plus the one already chosen so it still reads.
    private static func spans(
        of descriptor: DockWidgetDescriptor, including current: DockWidgetSpan
    ) -> [DockWidgetSpan] {
        var spans = descriptor.metadata.sizes.map { DockWidgetSpan($0) }
        if !spans.contains(current) { spans.append(current) }
        return spans
    }
}
