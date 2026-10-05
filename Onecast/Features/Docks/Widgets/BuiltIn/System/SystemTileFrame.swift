import SwiftUI

/// The padded space a System tile draws in; the dock itself draws the card behind it.
struct SystemTileFrame<Content: View>: View {
    let metrics: SystemTileMetrics
    let content: Content

    init(_ metrics: SystemTileMetrics, @ViewBuilder content: () -> Content) {
        self.metrics = metrics
        self.content = content()
    }

    var body: some View {
        content
            .padding(metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
