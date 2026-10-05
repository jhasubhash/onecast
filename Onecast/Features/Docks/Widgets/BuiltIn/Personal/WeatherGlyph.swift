import SwiftUI

/// A condition symbol in a tile's ink, sized as a fraction of the tile.
struct WeatherGlyph: View {
    let name: String
    let reading: WeatherTileReading
    let fraction: CGFloat

    var body: some View {
        SymbolImage(name: name, size: reading.metrics.symbolSize(fraction))
            .foregroundStyle(reading.ink.primary)
    }
}
