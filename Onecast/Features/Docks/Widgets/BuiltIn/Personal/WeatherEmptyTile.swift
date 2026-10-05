import SwiftUI

/// A tile with no reading yet, or none that could be got: muted, so it never passes for data.
struct WeatherEmptyTile: View {
    let metrics: PersonalTileMetrics

    var body: some View {
        VStack(spacing: metrics.spacing / 2) {
            SymbolImage(name: "cloud.sun", size: metrics.symbolSize(Self.glyph))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("—")
                .font(metrics.font(.display))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private static let glyph: CGFloat = 0.34
}
