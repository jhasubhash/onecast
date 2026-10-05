import SwiftUI

/// The scrollable hours ahead, the current hour first.
struct WeatherPopoverHours: View {
    let snapshot: WeatherModel.Snapshot
    let unit: PersonalWeatherUnit
    let now: Date

    var body: some View {
        let hours = snapshot.forecast.window(from: now, count: Self.hourCount)
        if !hours.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Next \(hours.count) hours")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textSecondary)
                ScrollView {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                            row(index, hour)
                        }
                    }
                }
                .frame(maxHeight: PersonalPopover.listMaxHeight)
            }
        }
    }

    private func row(_ index: Int, _ hour: PersonalWeatherForecast.Hour) -> some View {
        let time =
            index == 0
            ? "Now" : PersonalWeatherFormat.hour(hour.time, timeZone: snapshot.forecast.timeZone)
        let temperature = unit.temperature(fromCelsius: hour.temperature)
        return HStack(spacing: Theme.Spacing.md) {
            Text(time)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Self.timeColumn, alignment: .leading)
            SymbolImage(name: hour.condition.symbol, size: Self.glyph)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: Self.glyphColumn)
            if let chance = hour.precipitationChance, chance > 0 {
                Text(PersonalWeatherFormat.percent(chance))
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer(minLength: 0)
            Text(temperature)
                .font(Theme.Typography.rowTrailing.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(time), \(hour.condition.summary), \(temperature)")
    }

    private static let hourCount = 24
    private static let glyph: CGFloat = 16
    private static let glyphColumn: CGFloat = 24
    private static let timeColumn: CGFloat = 56
}
