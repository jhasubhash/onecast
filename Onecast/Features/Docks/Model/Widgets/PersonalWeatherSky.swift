import Foundation

/// The sky behind a themed weather tile, picked from nothing but the condition and daylight.
struct PersonalWeatherSky: Sendable, Equatable {
    enum Kind: Sendable, CaseIterable {
        case clear, partlyCloudy, overcast, fog, rain, snow, storm
    }

    struct RGB: Sendable, Equatable {
        let red: Double
        let green: Double
        let blue: Double

        /// WCAG relative luminance, so a tile can prove its ink stays legible.
        var luminance: Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    let kind: Kind
    let isDay: Bool

    /// An unknown or missing code reads as overcast: a neutral sky that claims nothing.
    init(code: Int?, isDay: Bool) {
        self.isDay = isDay
        switch code {
        case 0?, 1?: kind = .clear
        case 2?: kind = .partlyCloudy
        case 45?, 48?: kind = .fog
        case 51?, 53?, 55?, 56?, 57?, 61?, 63?, 65?, 66?, 67?, 80?, 81?, 82?: kind = .rain
        case 71?, 73?, 75?, 77?, 85?, 86?: kind = .snow
        case 95?, 96?, 99?: kind = .storm
        default: kind = .overcast
        }
    }

    /// The gradient's two stops, top to bottom.
    var colors: (top: RGB, bottom: RGB) {
        switch (kind, isDay) {
        case (.clear, true): (rgb(0.13, 0.42, 0.82), rgb(0.30, 0.58, 0.88))
        case (.clear, false): (rgb(0.06, 0.09, 0.26), rgb(0.16, 0.20, 0.42))
        case (.partlyCloudy, true): (rgb(0.22, 0.45, 0.74), rgb(0.42, 0.58, 0.78))
        case (.partlyCloudy, false): (rgb(0.09, 0.12, 0.28), rgb(0.24, 0.28, 0.44))
        case (.overcast, true): (rgb(0.36, 0.43, 0.52), rgb(0.50, 0.56, 0.63))
        case (.overcast, false): (rgb(0.14, 0.17, 0.23), rgb(0.26, 0.29, 0.36))
        case (.fog, true): (rgb(0.42, 0.47, 0.52), rgb(0.54, 0.58, 0.62))
        case (.fog, false): (rgb(0.20, 0.23, 0.27), rgb(0.31, 0.34, 0.38))
        case (.rain, true): (rgb(0.24, 0.32, 0.44), rgb(0.38, 0.47, 0.58))
        case (.rain, false): (rgb(0.09, 0.13, 0.22), rgb(0.19, 0.24, 0.34))
        case (.snow, true): (rgb(0.34, 0.46, 0.61), rgb(0.46, 0.57, 0.69))
        case (.snow, false): (rgb(0.16, 0.22, 0.34), rgb(0.30, 0.37, 0.50))
        case (.storm, true): (rgb(0.22, 0.20, 0.38), rgb(0.36, 0.34, 0.52))
        case (.storm, false): (rgb(0.10, 0.08, 0.22), rgb(0.22, 0.19, 0.38))
        }
    }

    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> RGB {
        RGB(red: red, green: green, blue: blue)
    }
}
