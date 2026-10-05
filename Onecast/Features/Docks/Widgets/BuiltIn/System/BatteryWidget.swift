import OnecastPluginKit
import SwiftUI

/// The Mac's battery: charge, charging state and time remaining, or "AC Power" without one.
final class BatteryWidget: OnecastDockWidget {
    static var metadata: DockWidgetMetadata {
        DockWidgetMetadata(
            name: "Battery", subtitle: "Charge, charging state and time remaining",
            icon: "battery.100percent", category: "System", sizes: [.compact, .wide])
    }

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(BatteryTileView(context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(BatteryPopoverView(context: context))
    }
}
