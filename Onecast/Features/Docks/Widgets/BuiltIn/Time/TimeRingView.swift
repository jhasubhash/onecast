import SwiftUI

/// A progress ring that fills clockwise from 12 o'clock.
struct TimeRingView: View {
    let fraction: Double
    let lineWidth: CGFloat
    var tint: Color = Theme.Colors.progress
    /// Set for a ring that advances every second, so it sweeps instead of stepping.
    var sweeps = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.separator, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(sweeps ? .linear(duration: 1) : nil, value: fraction)
        }
        .padding(lineWidth / 2)
    }
}
