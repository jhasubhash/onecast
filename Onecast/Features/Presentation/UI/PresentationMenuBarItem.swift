import SwiftUI

/// While presenting: a menu-bar sign that the screen is being shown, and the way out of it.
struct PresentationMenuBarLabel: View {
    var body: some View {
        Image(systemName: "record.circle")
            .accessibilityLabel("Presenting")
    }
}

/// The elapsed time lives here, read as the menu opens: a ticking label kept the scene rebuilding.
struct PresentationMenuBarMenu: View {
    private var coordinator: PresentationCoordinator { AppCore.shared.presentationCoordinator }

    var body: some View {
        Group {
            if let status { Text(status) }
            Button("Stop Presentation", systemImage: "stop.circle") { coordinator.stop() }
            Button("Re-fit Window", systemImage: "arrow.up.left.and.arrow.down.right") {
                coordinator.refit()
            }
            Divider()
            Button("Presentation Settings…", systemImage: "gearshape") {
                AppCore.shared.settingsCoordinator.showSettings(tab: .presentation)
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var status: String? {
        guard let startedAt = coordinator.startedAt else { return nil }
        let elapsed = TimeFormat.duration(Date().timeIntervalSince(startedAt))
        guard let app = coordinator.presentedApp?.localizedName else { return "Presenting · \(elapsed)" }
        return "Presenting \(app) · \(elapsed)"
    }
}
