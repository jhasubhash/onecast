import SwiftUI

/// A time tile's content area, padded and centred; the dock draws the card behind it.
struct TimeTileContent<Content: View>: View {
    let metrics: TimeTileMetrics
    let content: Content

    init(_ metrics: TimeTileMetrics, @ViewBuilder content: () -> Content) {
        self.metrics = metrics
        self.content = content()
    }

    var body: some View {
        content
            .padding(metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Text {
    /// One line that shrinks before it clips, in tabular figures so a ticking time never jitters.
    func timeFigure(_ font: Font, color: Color = Theme.Colors.textPrimary) -> some View {
        self.font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .foregroundStyle(color)
    }
}
