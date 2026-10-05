import SwiftUI

/// A ring filled clockwise from the top to `progress`; values outside 0...1 clamp.
struct PersonalProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.controlSurface, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}
