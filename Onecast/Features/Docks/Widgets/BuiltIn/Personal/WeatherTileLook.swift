import SwiftUI

/// A Weather tile's paint: a sky gradient with white ink, or the host's card with the palette's.
struct WeatherTileLook {
    struct Ink {
        let primary: Color
        let secondary: Color
        /// The header's dot, tinted by what the sky is doing.
        let accent: Color
    }

    /// Nil leaves the host's own card showing: Translucent, or no reading to take a sky from.
    let gradient: LinearGradient?
    let ink: Ink

    init(snapshot: WeatherModel.Snapshot?, background: PersonalWeatherSettings.Background) {
        guard let current = snapshot?.forecast.current else {
            gradient = nil
            ink = Ink(
                primary: Theme.Colors.textPrimary, secondary: Theme.Colors.textSecondary,
                accent: Theme.Colors.textTertiary)
            return
        }
        let sky = PersonalWeatherSky(code: current.weatherCode, isDay: current.isDay)
        guard background == .themed else {
            gradient = nil
            ink = Ink(
                primary: Theme.Colors.textPrimary, secondary: Theme.Colors.textSecondary,
                accent: Self.accent(for: sky.kind, fallback: Theme.Colors.textPrimary))
            return
        }
        let stops = sky.colors
        gradient = LinearGradient(
            colors: [Self.color(stops.top), Self.color(stops.bottom)],
            startPoint: .top, endPoint: .bottom)
        // A saturated sky carries its own contrast, so its ink stays white in both appearances.
        ink = Ink(
            primary: .white, secondary: Color.white.opacity(Self.skySecondaryOpacity),
            accent: Self.accent(for: sky.kind, fallback: .white))
    }

    private static let skySecondaryOpacity = 0.78

    private static func accent(for kind: PersonalWeatherSky.Kind, fallback: Color) -> Color {
        switch kind {
        case .clear, .partlyCloudy: .yellow
        case .rain: .cyan
        case .snow: .mint
        case .storm: .orange
        case .overcast, .fog: fallback
        }
    }

    private static func color(_ rgb: PersonalWeatherSky.RGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}
