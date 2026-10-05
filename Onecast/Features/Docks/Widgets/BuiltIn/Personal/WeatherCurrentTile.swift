import SwiftUI

/// The Current display: the temperature and its symbol, with the city and feels-like around it.
struct WeatherCurrentTile: View {
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

    private var glyph: some View {
        WeatherGlyph(name: reading.condition.symbol, reading: reading, fraction: Self.glyph)
    }

    private var temperature: some View {
        WeatherTileText(
            text: reading.temperature(reading.current.temperature), role: .display, reading: reading)
    }

    private var header: some View {
        WeatherTileHeader(title: reading.snapshot.place.name, reading: reading)
    }

    private var compact: some View {
        VStack(spacing: reading.metrics.spacing / 2) {
            glyph
            temperature
        }
    }

    private var column: some View {
        VStack(spacing: reading.metrics.spacing) {
            header
            glyph
            temperature
            caption(reading.condition.summary)
            if reading.isExpanded {
                if let feelsLike = reading.feelsLike { caption(feelsLike) }
                if let highLow = reading.highLow { caption(highLow) }
            }
        }
    }

    private var row: some View {
        HStack(spacing: reading.metrics.spacing * 2) {
            VStack(spacing: reading.metrics.spacing / 2) {
                glyph
                temperature
            }
            VStack(spacing: reading.metrics.spacing / 2) {
                header
                if let feelsLike = reading.feelsLike { caption(feelsLike) }
            }
            if reading.isExpanded {
                VStack(spacing: reading.metrics.spacing / 2) {
                    caption(reading.condition.summary)
                    if let highLow = reading.highLow { caption(highLow) }
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        WeatherTileText(text: text, role: .caption, reading: reading, secondary: true)
    }

    private static let glyph: CGFloat = 0.34
}
