import Foundation

/// One forecast response as plain values: Celsius, km/h, and instants in the place's own zone.
struct PersonalWeatherForecast: Sendable, Equatable {
    struct Current: Sendable, Equatable {
        let temperature: Double
        let apparentTemperature: Double?
        let weatherCode: Int?
        let isDay: Bool
        let windSpeed: Double?
        let humidity: Int?

        var condition: PersonalWeatherCondition {
            PersonalWeatherCondition(code: weatherCode, isDay: isDay)
        }
    }

    struct Hour: Sendable, Equatable, Identifiable {
        /// The start of the hour.
        let time: Date
        let temperature: Double
        let weatherCode: Int?
        /// Nil when the response did not say, which draws the daytime symbol.
        let isDay: Bool?
        let precipitationChance: Int?

        var id: Date { time }

        var condition: PersonalWeatherCondition {
            PersonalWeatherCondition(code: weatherCode, isDay: isDay ?? true)
        }
    }

    let current: Current
    /// Ascending by time.
    let hours: [Hour]
    let todayHigh: Double?
    let todayLow: Double?
    /// The place's zone, which hour labels are drawn in rather than the Mac's.
    let timeZone: TimeZone

    /// Up to `count` hours from the one `now` falls in, across midnight; empty past the data.
    func window(from now: Date, count: Int) -> [Hour] {
        guard count > 0 else { return [] }
        let upcoming = hours.drop { $0.time.addingTimeInterval(Self.hour) <= now }
        return Array(upcoming.prefix(count))
    }

    private static let hour: TimeInterval = 3600
}
