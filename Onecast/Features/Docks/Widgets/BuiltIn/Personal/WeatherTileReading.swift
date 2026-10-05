import SwiftUI

/// Everything one Weather tile layout draws from, so each layout takes a single value.
struct WeatherTileReading {
    let snapshot: WeatherModel.Snapshot
    let settings: PersonalWeatherSettings
    let metrics: PersonalTileMetrics
    let ink: WeatherTileLook.Ink

    var forecast: PersonalWeatherForecast { snapshot.forecast }
    var current: PersonalWeatherForecast.Current { snapshot.forecast.current }
    var condition: PersonalWeatherCondition { current.condition }

    var isExpanded: Bool { metrics.size == .expanded }

    func temperature(_ celsius: Double) -> String {
        settings.unit.temperature(fromCelsius: celsius)
    }

    var feelsLike: String? {
        current.apparentTemperature.map { "Feels \(temperature($0))" }
    }

    var highLow: String? {
        guard let high = forecast.todayHigh, let low = forecast.todayLow else { return nil }
        return "H \(temperature(high))  L \(temperature(low))"
    }

    var humidity: String? {
        current.humidity.map { PersonalWeatherFormat.percent($0) }
    }

    var wind: String? {
        current.windSpeed.map { settings.unit.windSpeed(fromKilometersPerHour: $0) }
    }
}
