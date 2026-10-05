import SwiftUI

/// One line of tile text in a role's type, shrinking before it truncates.
struct WeatherTileText: View {
    let text: String
    let role: PersonalTileMetrics.Role
    let reading: WeatherTileReading
    var secondary = false
    var lines = 1

    var body: some View {
        Text(text)
            .font(reading.metrics.font(role, weight: secondary ? .medium : .semibold))
            .foregroundStyle(secondary ? reading.ink.secondary : reading.ink.primary)
            .lineLimit(lines)
            .minimumScaleFactor(Self.shrink)
            .multilineTextAlignment(.center)
    }

    private static let shrink: CGFloat = 0.6
}
