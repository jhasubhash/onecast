import OnecastPluginKit
import SwiftUI

/// Presentation Mode in the dock: its state at a glance, a one-click toggle, and its settings.
final class PresentationDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Presentation", subtitle: "Screen-sharing mode in one click",
        icon: PresentationDockWidget.symbol, category: "Productivity",
        sizes: [.compact, .wide, .expanded])

    static let symbol = "rectangle.inset.filled.and.person.filled"

    /// Seconds only while presenting, for the elapsed time; otherwise the shared clock idles.
    private let lease = TimeTickLease(needsSeconds: {
        AppCore.shared.presentationCoordinator.isPresenting
    })

    /// The dock asks for the popover on every click in the tile, a button's included.
    private var isPointerOnControl = false

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(
            PresentationTileView(
                context: context, onPhaseChange: { [lease] in lease.reevaluate() },
                onControlHover: { [weak self] in self?.isPointerOnControl = $0 }))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        guard !isPointerOnControl else { return nil }
        return AnyView(PresentationPopoverView(context: context))
    }

    func didRemove() {
        lease.release()
    }
}
