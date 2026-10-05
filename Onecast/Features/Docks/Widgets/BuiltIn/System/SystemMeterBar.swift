import SwiftUI

/// A horizontal gauge: a quiet track with a filled run, or several runs in sequence.
struct SystemMeterBar: View {
    struct Segment: Identifiable {
        let id: String
        let fraction: Double
        let tint: Color
    }

    static let defaultHeight = Theme.Spacing.md

    let segments: [Segment]
    let height: CGFloat

    init(fraction: Double, tint: Color, height: CGFloat = SystemMeterBar.defaultHeight) {
        segments = [Segment(id: "value", fraction: fraction, tint: tint)]
        self.height = height
    }

    init(segments: [Segment], height: CGFloat = SystemMeterBar.defaultHeight) {
        self.segments = segments
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.tint)
                        .frame(width: proxy.size.width * min(max(segment.fraction, 0), 1))
                }
                Spacer(minLength: 0)
            }
            .background(Theme.Colors.controlSurface)
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
