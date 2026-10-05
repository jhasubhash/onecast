import OnecastPluginKit
import SwiftUI

/// Weather for a city or for where the Mac is: the temperature, the sky, or the hours ahead.
final class WeatherDockWidget: OnecastDockWidget {
    private let model = WeatherModel()

    static var metadata: DockWidgetMetadata {
        DockWidgetMetadata(
            name: "Weather", subtitle: "The temperature and the hours ahead", icon: "cloud.sun",
            category: "Personal", sizes: [.compact, .wide, .expanded])
    }

    static let preferences: [PluginPreference] = [
        PluginPreference(
            name: PersonalWeatherSettings.Name.location, title: "City",
            description: "A city such as Cupertino, or Paris, FR to say which Paris. "
                + "Ignored while Use current location is on.",
            placeholder: "Cupertino", kind: .textfield),
        PluginPreference(
            name: PersonalWeatherSettings.Name.useCurrentLocation, title: "Use current location",
            description: "Asks for location access the first time this is turned on.",
            kind: .checkbox, defaultValue: .bool(false)),
        PluginPreference(
            name: PersonalWeatherSettings.Name.display, title: "Display", kind: .dropdown,
            options: [
                PluginPreference.Option(title: "Current", value: "current"),
                PluginPreference.Option(title: "Conditions", value: "conditions"),
                PluginPreference.Option(title: "Hourly forecast", value: "hourly"),
            ], defaultValue: .string("current")),
        PluginPreference(
            name: PersonalWeatherSettings.Name.unit, title: "Unit", kind: .dropdown,
            options: [
                PluginPreference.Option(title: "Celsius", value: "celsius"),
                PluginPreference.Option(title: "Fahrenheit", value: "fahrenheit"),
            ], defaultValue: .string(PersonalWeatherUnit.localeDefault().rawValue)),
        PluginPreference(
            name: PersonalWeatherSettings.Name.forecastHours, title: "Forecast hours",
            description: "How many hours the hourly forecast shows; a side dock shows up to 3.",
            kind: .dropdown,
            options: PersonalWeatherSettings.forecastHourRange.map {
                PluginPreference.Option(title: $0 == 1 ? "1 hour" : "\($0) hours", value: "\($0)")
            }, defaultValue: .string("\(PersonalWeatherSettings.defaultForecastHours)")),
        PluginPreference(
            name: PersonalWeatherSettings.Name.background, title: "Background", kind: .dropdown,
            options: [
                PluginPreference.Option(title: "Themed", value: "themed"),
                PluginPreference.Option(title: "Translucent", value: "translucent"),
            ], defaultValue: .string("themed")),
    ]

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(WeatherTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(WeatherPopoverView(model: model, context: context))
    }

    func didRemove() {
        model.stop()
    }
}
