import Foundation

/// The temperature scale a weather tile shows. Parsed values stay Celsius and km/h; this converts.
enum PersonalWeatherUnit: String, Sendable, CaseIterable {
    case celsius
    case fahrenheit

    /// Fahrenheit where the region measures in US units, Celsius everywhere else.
    static func localeDefault(_ locale: Locale = .current) -> PersonalWeatherUnit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// A stored preference, or the locale's default when it is unset or not a unit.
    init(preference: String?, locale: Locale = .current) {
        self = preference.flatMap(Self.init(rawValue:)) ?? Self.localeDefault(locale)
    }

    func degrees(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    /// Whole degrees, halves away from zero; a value that rounds to zero is never "-0".
    func roundedDegrees(fromCelsius celsius: Double) -> Int {
        Int(degrees(fromCelsius: celsius).rounded(.toNearestOrAwayFromZero))
    }

    func temperature(fromCelsius celsius: Double, locale: Locale = .current) -> String {
        number(roundedDegrees(fromCelsius: celsius), locale: locale) + "°"
    }

    func windSpeed(fromKilometersPerHour speed: Double, locale: Locale = .current) -> String {
        switch self {
        case .celsius:
            return number(Int(speed.rounded(.toNearestOrAwayFromZero)), locale: locale) + " km/h"
        case .fahrenheit:
            let miles = speed * Self.milesPerKilometer
            return number(Int(miles.rounded(.toNearestOrAwayFromZero)), locale: locale) + " mph"
        }
    }

    private static let milesPerKilometer = 0.621371

    private func number(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.grouping(.never).locale(locale))
    }
}
