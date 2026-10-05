import OnecastPluginKit
import SwiftUI

/// CPU, memory and storage at a glance, with a tabbed popover for the detail behind each.
final class SystemActivityWidget: OnecastDockWidget {
    enum PreferenceName {
        static let metric = "metric"
    }

    static var metadata: DockWidgetMetadata {
        DockWidgetMetadata(
            name: "System Activity", subtitle: "CPU, memory and storage",
            icon: "cpu", category: "System", sizes: [.compact, .wide, .expanded])
    }

    static let preferences = [
        PluginPreference(
            name: PreferenceName.metric, title: "Lead with", kind: .dropdown,
            options: SystemActivityMetric.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            }, defaultValue: .string(SystemActivityMetric.cpu.rawValue))
    ]

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(SystemActivityTileView(context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(SystemActivityPopoverView(context: context))
    }
}
