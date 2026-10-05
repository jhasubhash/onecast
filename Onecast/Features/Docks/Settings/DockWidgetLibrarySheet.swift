import OnecastPluginKit
import SwiftUI

/// Every widget Onecast can show — built in or installed — grouped by category, to add to a layout.
struct DockWidgetLibrarySheet: View {
    let dockID: UUID
    let layoutID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @State private var query = ""

    private var widgets: DockWidgetManager { core.dockCoordinator.widgets }

    private struct Category: Identifiable {
        let name: String
        let descriptors: [DockWidgetDescriptor]
        var id: String { name }
    }

    /// Categories in the order the catalog first meets them, so the library reads as it was built.
    private var categories: [Category] {
        let shown = widgets.catalog.filter(isShown)
        var order: [String] = []
        for descriptor in shown where !order.contains(descriptor.metadata.category) {
            order.append(descriptor.metadata.category)
        }
        return order.map { name in
            Category(name: name, descriptors: shown.filter { $0.metadata.category == name })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Add Widget")
                .font(.title2.weight(.bold))

            TextField("", text: $query, prompt: Text("Search widgets"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityLabel("Search widgets")

            list

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    @ViewBuilder
    private var list: some View {
        let categories = categories
        if categories.isEmpty {
            Text(query.isEmpty ? "No widgets are installed." : "No widget matches “\(query)”.")
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity, minHeight: DockSettingsMetrics.widgetSheetListHeight,
                    alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(categories) { category in
                        Text(category.name)
                            .font(Theme.Typography.sectionHeader)
                            .foregroundStyle(.secondary)
                            .padding(.top, Theme.Spacing.sm)
                        ForEach(category.descriptors) { descriptor in
                            row(descriptor)
                        }
                    }
                }
            }
            .frame(height: DockSettingsMetrics.widgetSheetListHeight)
            .overflowFade(band: Theme.Size.menuOverflowFade)
        }
    }

    private func row(_ descriptor: DockWidgetDescriptor) -> some View {
        let metadata = descriptor.metadata
        return HStack(spacing: Theme.Spacing.lg) {
            DockSymbolTile(name: metadata.icon, size: DockSettingsMetrics.widgetRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(metadata.name).lineLimit(1)
                    if !descriptor.isBuiltIn {
                        Text("Third-party")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !metadata.subtitle.isEmpty {
                    Text(metadata.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(sizeSummary(metadata.sizes))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: Theme.Spacing.md)
            Button("Add") {
                core.dockCoordinator.addWidget(
                    descriptor.id, span: DockWidgetSpan(metadata.sizes[0]), dockID: dockID,
                    layoutID: layoutID)
                dismiss()
            }
            .accessibilityLabel("Add \(metadata.name)")
        }
    }

    private func sizeSummary(_ sizes: [DockWidgetSize]) -> String {
        sizes.map { DockWidgetSpan($0).settingsTitle }.joined(separator: " · ")
    }

    private func isShown(_ descriptor: DockWidgetDescriptor) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let metadata = descriptor.metadata
        return [metadata.name, metadata.subtitle, metadata.category].contains {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }
}
