import Foundation

/// A WMO weather code, as Open-Meteo reports it, drawn as an SF Symbol with a short description.
struct PersonalWeatherCondition: Sendable, Equatable {
    let symbol: String
    let summary: String

    /// What a code outside the table, or a missing one, shows instead of a wrong guess.
    static let unknown = PersonalWeatherCondition(symbol: "questionmark.circle", summary: "Unknown")

    init(symbol: String, summary: String) {
        self.symbol = symbol
        self.summary = summary
    }

    init(code: Int?, isDay: Bool) {
        guard let code, let entry = Self.table[code] else {
            self = .unknown
            return
        }
        self.init(symbol: isDay ? entry.day : entry.night, summary: entry.summary)
    }

    /// Every code the Open-Meteo documentation lists, in ascending order.
    static var documentedCodes: [Int] { table.keys.sorted() }

    private struct Entry {
        let day: String
        let night: String
        let summary: String

        init(_ symbol: String, _ summary: String) {
            self.init(symbol, symbol, summary)
        }

        init(_ day: String, _ night: String, _ summary: String) {
            self.day = day
            self.night = night
            self.summary = summary
        }
    }

    private static let table: [Int: Entry] = [
        0: Entry("sun.max", "moon.stars", "Clear sky"),
        1: Entry("sun.max", "moon.stars", "Mainly clear"),
        2: Entry("cloud.sun", "cloud.moon", "Partly cloudy"),
        3: Entry("cloud", "Overcast"),
        45: Entry("cloud.fog", "Fog"),
        48: Entry("cloud.fog", "Rime fog"),
        51: Entry("cloud.drizzle", "Light drizzle"),
        53: Entry("cloud.drizzle", "Drizzle"),
        55: Entry("cloud.drizzle", "Heavy drizzle"),
        56: Entry("cloud.sleet", "Freezing drizzle"),
        57: Entry("cloud.sleet", "Heavy freezing drizzle"),
        61: Entry("cloud.rain", "Light rain"),
        63: Entry("cloud.rain", "Rain"),
        65: Entry("cloud.heavyrain", "Heavy rain"),
        66: Entry("cloud.sleet", "Freezing rain"),
        67: Entry("cloud.sleet", "Heavy freezing rain"),
        71: Entry("cloud.snow", "Light snow"),
        73: Entry("cloud.snow", "Snow"),
        75: Entry("cloud.snow", "Heavy snow"),
        77: Entry("snowflake", "Snow grains"),
        80: Entry("cloud.sun.rain", "cloud.moon.rain", "Light showers"),
        81: Entry("cloud.sun.rain", "cloud.moon.rain", "Showers"),
        82: Entry("cloud.heavyrain", "Heavy showers"),
        85: Entry("cloud.snow", "Light snow showers"),
        86: Entry("cloud.snow", "Heavy snow showers"),
        95: Entry("cloud.bolt.rain", "Thunderstorm"),
        96: Entry("cloud.bolt.rain", "Thunderstorm, light hail"),
        99: Entry("cloud.bolt.rain", "Thunderstorm, heavy hail"),
    ]
}
