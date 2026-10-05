import AppKit
import SwiftUI

/// Settings › Docks › DockWidgets: the consent switch, installed widgets and their build state.
struct DockWidgetsSettingsSection: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        let widgets = core.dockCoordinator.widgets
        let enabled = core.settings.dockWidgetsEnabled
        Section {
            Toggle(
                isOn: Binding(
                    get: { core.settings.dockWidgetsEnabled },
                    set: { core.dockCoordinator.setDockWidgetsEnabled($0) })
            ) {
                SettingsRowTitle(.docksDockWidgets, "Allow third-party DockWidgets")
                Text(
                    "A DockWidget is compiled Swift that runs inside Onecast with full access to "
                    + "this Mac — allow only widgets whose source you have read.")
            }
            Group {
                if widgets.installed.isEmpty {
                    Text(
                        enabled
                            ? "No DockWidgets installed."
                            : "Allow third-party DockWidgets to load the ones in your folder."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(widgets.installed) { install in
                        InstalledDockWidgetRow(install: install)
                    }
                }
                Button("Reveal DockWidgets Folder…") {
                    NSWorkspace.shared.activateFileViewerSelecting([DockWidgetCatalog.widgetsDirectory()])
                }
            }
            .settingsEnabled(enabled)
        } header: {
            SettingsSectionHeader(.docksDockWidgets)
        }
    }
}

/// An installed widget: its identity, whether it built, and the compiler's output when it did not.
private struct InstalledDockWidgetRow: View {
    @Environment(AppCore.self) private var core
    let install: DockWidgetInstall

    var body: some View {
        let state = core.dockCoordinator.widgets.state(forWidgetID: install.id)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SymbolImage(name: install.manifest.icon, size: 14)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(install.manifest.name)
                    if !install.manifest.subtitle.isEmpty {
                        Text(install.manifest.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if state == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Building \(install.manifest.name)")
                }
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([install.directory])
                }
                Button("Uninstall", role: .destructive, action: confirmUninstall)
            }
            if case .failed(let message) = state {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.Colors.warning)
                    .textSelection(.enabled)
                    .padding(.leading, 20 + Theme.Spacing.sm)
            }
        }
    }

    private func confirmUninstall() {
        Task {
            let confirmed = await core.confirm(
                title: "Uninstall “\(install.manifest.name)”?",
                message: "Its folder is deleted. Tiles on your docks that use it show a warning.",
                symbol: "trash", confirmTitle: "Uninstall")
            if confirmed { core.dockCoordinator.widgets.uninstall(install) }
        }
    }
}
