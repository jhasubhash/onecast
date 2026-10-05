import SwiftUI

/// The Hourly forecast display: the next hours as columns on a bottom dock, rows on a side dock.
struct WeatherHourlyTile: View {
    let reading: WeatherTileReading

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tick)) { timeline in
            let hours = reading.forecast.window(
                from: timeline.date,
                count: reading.settings.visibleHours(isVertical: reading.metrics.isVertical))
            if hours.isEmpty {
                WeatherCurrentTile(reading: reading)
            } else if reading.metrics.isVertical {
                rows(hours)
            } else {
                columns(hours)
            }
        }
    }

    private func label(_ index: Int, _ hour: PersonalWeatherForecast.Hour) -> String {
        index == 0
            ? "Now" : PersonalWeatherFormat.hour(hour.time, timeZone: reading.forecast.timeZone)
    }

    // MARK: Bottom dock

    private func columns(_ hours: [PersonalWeatherForecast.Hour]) -> some View {
        GeometryReader { proxy in
            let fit = max(1, Int(proxy.size.width / (reading.metrics.tileLength * Self.columnWidth)))
            HStack(spacing: 0) {
                ForEach(Array(hours.prefix(fit).enumerated()), id: \.element.id) { index, hour in
                    column(index, hour)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func column(_ index: Int, _ hour: PersonalWeatherForecast.Hour) -> some View {
        VStack(spacing: reading.metrics.spacing / 2) {
            WeatherTileText(text: label(index, hour), role: .caption, reading: reading, secondary: true)
            WeatherGlyph(name: hour.condition.symbol, reading: reading, fraction: Self.glyph)
            WeatherTileText(text: reading.temperature(hour.temperature), role: .label, reading: reading)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Side dock

    private func rows(_ hours: [PersonalWeatherForecast.Hour]) -> some View {
        VStack(spacing: reading.metrics.spacing) {
            WeatherTileHeader(title: reading.snapshot.place.name, reading: reading)
            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                row(index, hour)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func row(_ index: Int, _ hour: PersonalWeatherForecast.Hour) -> some View {
        HStack(spacing: reading.metrics.spacing) {
            WeatherGlyph(name: hour.condition.symbol, reading: reading, fraction: Self.glyph)
            VStack(spacing: 0) {
                WeatherTileText(
                    text: label(index, hour), role: .caption, reading: reading, secondary: true)
                WeatherTileText(
                    text: reading.temperature(hour.temperature), role: .label, reading: reading)
            }
        }
    }

    /// A column's least width, as a fraction of the tile; fewer hours are drawn than would crowd.
    private static let columnWidth: CGFloat = 0.4
    private static let glyph: CGFloat = 0.24
    private static let tick: TimeInterval = 60
}
