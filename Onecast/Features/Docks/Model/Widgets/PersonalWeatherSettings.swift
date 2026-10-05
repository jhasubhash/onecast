import Foundation

/// A Weather widget instance's own settings, parsed from its preferences with every value clamped.
struct PersonalWeatherSettings: Sendable, Equatable {
    enum Display: String, Sendable {
        case current
        case conditions
        case hourly
    }

    enum Background: String, Sendable {
        case themed
        case translucent
    }

    /// Where the weather is read for; each case that changes this refetches, nothing else does.
    enum Source: Sendable, Equatable {
        case unset
        case current
        case city(PersonalWeatherPlaceQuery)
    }

    /// The preference names the widget declares.
    enum Name {
        static let location = "location"
        static let useCurrentLocation = "useCurrentLocation"
        static let display = "display"
        static let unit = "unit"
        static let forecastHours = "forecastHours"
        static let background = "background"
    }

    static let forecastHourRange = 1...6
    static let defaultForecastHours = 4
    /// A side dock lays hours out as rows, and a tile only has room for this many of them.
    static let verticalForecastHours = 3

    let display: Display
    let unit: PersonalWeatherUnit
    let forecastHours: Int
    let background: Background
    let source: Source

    init(
        string: (String) -> String?, bool: (String) -> Bool, locale: Locale = .current
    ) {
        display = string(Name.display).flatMap(Display.init(rawValue:)) ?? .current
        unit = PersonalWeatherUnit(preference: string(Name.unit), locale: locale)
        let hours = string(Name.forecastHours)
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        forecastHours = min(
            max(hours ?? Self.defaultForecastHours, Self.forecastHourRange.lowerBound),
            Self.forecastHourRange.upperBound)
        background = string(Name.background).flatMap(Background.init(rawValue:)) ?? .themed
        if bool(Name.useCurrentLocation) {
            source = .current
        } else if let query = string(Name.location).flatMap(PersonalWeatherPlaceQuery.init) {
            source = .city(query)
        } else {
            source = .unset
        }
    }

    /// How many hours the tile lists on this dock.
    func visibleHours(isVertical: Bool) -> Int {
        isVertical ? min(forecastHours, Self.verticalForecastHours) : forecastHours
    }
}
