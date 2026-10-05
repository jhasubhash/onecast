import SwiftUI

/// Re-renders its content on the shared clock, handing it the moment to draw.
struct TimeLiveView<Content: View>: View {
    enum Granularity {
        case second, minute
    }

    let granularity: Granularity
    @ViewBuilder let content: (Date) -> Content
    private let clock = DockWidgetServices.current.clock

    var body: some View {
        // A tick that has not landed yet must not show a stale time, so the wall clock can win.
        let tick = granularity == .second ? clock.now : clock.minute
        content(max(Date(), tick))
    }
}
