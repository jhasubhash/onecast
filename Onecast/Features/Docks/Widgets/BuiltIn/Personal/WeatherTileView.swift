import OnecastPluginKit
import SwiftUI

/// The dock tile: the display the settings choose, over a sky gradient or the host's own card.
struct WeatherTileView: View {
    let model: WeatherModel
    let context: DockWidgetContext

    var body: some View {
        let metrics = PersonalTileMetrics(context)
        let settings = model.settings(for: context)
        let look = WeatherTileLook(snapshot: model.snapshot, background: settings.background)
        PersonalTileCard(metrics) {
            content(metrics: metrics, settings: settings, ink: look.ink)
        }
        .background {
            if let gradient = look.gradient { gradient }
        }
        .task(id: context.instanceID) { await model.run(context: context) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(settings))
    }

    @ViewBuilder
    private func content(
        metrics: PersonalTileMetrics, settings: PersonalWeatherSettings, ink: WeatherTileLook.Ink
    ) -> some View {
        if let snapshot = model.snapshot {
            let reading = WeatherTileReading(
                snapshot: snapshot, settings: settings, metrics: metrics, ink: ink)
            display(reading)
                .opacity(model.failure == nil ? 1 : Self.staleOpacity)
        } else {
            WeatherEmptyTile(metrics: metrics)
        }
    }

    /// A compact tile has no room for an hour list, so it falls back to the Current display.
    @ViewBuilder
    private func display(_ reading: WeatherTileReading) -> some View {
        switch reading.settings.display {
        case .current: WeatherCurrentTile(reading: reading)
        case .conditions: WeatherConditionsTile(reading: reading)
        case .hourly:
            if reading.metrics.isCompact {
                WeatherCurrentTile(reading: reading)
            } else {
                WeatherHourlyTile(reading: reading)
            }
        }
    }

    private func accessibilityLabel(_ settings: PersonalWeatherSettings) -> String {
        guard let snapshot = model.snapshot else {
            return "Weather unavailable. " + (model.failure?.message ?? "Loading.")
        }
        let current = snapshot.forecast.current
        let temperature = settings.unit.temperature(fromCelsius: current.temperature)
        let label = "Weather, \(snapshot.place.name), \(temperature), \(current.condition.summary)"
        return model.failure == nil ? label : label + ". Out of date."
    }

    private static let staleOpacity = 0.5
}
