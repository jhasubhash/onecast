import SwiftUI

/// The Conditions display: the symbol first, then what the sky is doing and the day's range.
struct WeatherConditionsTile: View {
    let reading: WeatherTileReading

    var body: some View {
        if reading.metrics.isCompact {
            compact
        } else if reading.metrics.isVertical {
            column
        } else {
            row
        }
    }

    private var temperature: some View {
        WeatherTileText(
            text: reading.temperature(reading.current.temperature), role: .value, reading: reading)
    }

    private var summary: some View {
        WeatherTileText(text: reading.condition.summary, role: .label, reading: reading, lines: 2)
    }

    private func glyph(_ fraction: CGFloat) -> some View {
        WeatherGlyph(name: reading.condition.symbol, reading: reading, fraction: fraction)
    }

    @ViewBuilder
    private var highLow: some View {
        if let text = reading.highLow {
            WeatherTileText(text: text, role: .caption, reading: reading, secondary: true)
        }
    }

    private var compact: some View {
        VStack(spacing: reading.metrics.spacing / 2) {
            glyph(Self.compactGlyph)
            temperature
        }
    }

    private var column: some View {
        VStack(spacing: reading.metrics.spacing) {
            WeatherTileHeader(title: reading.snapshot.place.name, reading: reading)
            glyph(Self.glyph)
            summary
            temperature
            highLow
            if reading.isExpanded { surroundings }
        }
    }

    private var row: some View {
        HStack(spacing: reading.metrics.spacing * 2) {
            glyph(Self.glyph)
            VStack(spacing: reading.metrics.spacing / 2) {
                summary
                temperature
                highLow
            }
            if reading.isExpanded {
                VStack(spacing: reading.metrics.spacing / 2) { surroundings }
            }
        }
    }

    /// Humidity and wind, for the tiles long enough to carry them.
    @ViewBuilder
    private var surroundings: some View {
        if let humidity = reading.humidity {
            WeatherTileFact(symbol: "humidity", text: humidity, reading: reading)
        }
        if let wind = reading.wind {
            WeatherTileFact(symbol: "wind", text: wind, reading: reading)
        }
    }

    private static let compactGlyph: CGFloat = 0.44
    private static let glyph: CGFloat = 0.5
}
