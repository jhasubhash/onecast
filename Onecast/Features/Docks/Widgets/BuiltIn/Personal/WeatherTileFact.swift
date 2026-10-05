import SwiftUI

/// A small symbol and value on one line, for the facts a long tile has room to add.
struct WeatherTileFact: View {
    let symbol: String
    let text: String
    let reading: WeatherTileReading

    var body: some View {
        HStack(spacing: reading.metrics.spacing / 2) {
            SymbolImage(name: symbol, size: reading.metrics.symbolSize(Self.glyph))
                .foregroundStyle(reading.ink.secondary)
            WeatherTileText(text: text, role: .caption, reading: reading, secondary: true)
        }
    }

    private static let glyph: CGFloat = 0.14
}
