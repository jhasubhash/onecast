import OnecastPluginKit
import SwiftUI

/// Upload and download throughput from the interface byte counters, with a short history graph.
final class NetworkActivityWidget: OnecastDockWidget {
    enum PreferenceName {
        static let scope = "scope"
    }

    static var metadata: DockWidgetMetadata {
        DockWidgetMetadata(
            name: "Network Activity", subtitle: "Live upload and download speed",
            icon: "arrow.up.arrow.down", category: "System", sizes: [.wide, .compact, .expanded])
    }

    static let preferences = [
        PluginPreference(
            name: PreferenceName.scope, title: "Measure", kind: .dropdown,
            options: [
                PluginPreference.Option(title: "Primary interface", value: "primary"),
                PluginPreference.Option(title: "All interfaces", value: "total"),
            ], defaultValue: .string("primary"))
    ]

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(NetworkActivityTileView(context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(NetworkActivityPopoverView(context: context))
    }
}
