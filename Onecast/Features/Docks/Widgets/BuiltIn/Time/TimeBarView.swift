import SwiftUI

/// A horizontal progress bar: a quiet track with a rounded fill.
struct TimeBarView: View {
    let fraction: Double
    let height: CGFloat
    var tint: Color = Theme.Colors.progress

    var body: some View {
        Capsule()
            .fill(Theme.Colors.separator)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(Capsule())
    }
}
