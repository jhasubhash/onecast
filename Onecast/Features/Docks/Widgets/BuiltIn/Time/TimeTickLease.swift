import Foundation

/// A widget's subscription to the shared clock, released when the widget is removed or dropped.
@MainActor
final class TimeTickLease {
    private var id: UUID?

    init(
        needsSeconds: @escaping @MainActor () -> Bool = { false },
        onTick: @escaping @MainActor (Date) -> Void = { _ in }
    ) {
        id = DockWidgetServices.current.clock.subscribe(needsSeconds: needsSeconds, onTick: onTick)
    }

    /// Call after the widget's own state changed whether it needs a per-second tick.
    func reevaluate() {
        DockWidgetServices.current.clock.reevaluate()
    }

    func release() {
        guard let id else { return }
        DockWidgetServices.current.clock.unsubscribe(id)
        self.id = nil
    }

    isolated deinit {
        release()
    }
}
