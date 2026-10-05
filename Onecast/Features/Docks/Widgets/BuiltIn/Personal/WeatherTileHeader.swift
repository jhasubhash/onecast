import SwiftUI

/// A tile's top line in the tile's own ink: an accent dot and a short label that truncates.
struct WeatherTileHeader: View {
    let title: String
    let reading: WeatherTileReading

    var body: some View {
        HStack(spacing: reading.metrics.spacing) {
            Circle()
                .fill(reading.ink.accent)
                .frame(width: reading.metrics.dotSize, height: reading.metrics.dotSize)
            Text(title)
                .font(reading.metrics.font(.caption, weight: .medium))
                .foregroundStyle(reading.ink.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
