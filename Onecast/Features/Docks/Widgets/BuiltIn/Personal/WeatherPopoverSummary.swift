import SwiftUI

/// The popover's head: the place, and the current reading in full.
struct WeatherPopoverSummary: View {
    let snapshot: WeatherModel.Snapshot
    let unit: PersonalWeatherUnit

    var body: some View {
        let forecast = snapshot.forecast
        let current = forecast.current
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.place.name)
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let region = snapshot.place.region {
                    Text(region)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                SymbolImage(name: current.condition.symbol, size: Self.glyph)
                    .foregroundStyle(Theme.Colors.textPrimary)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(unit.temperature(fromCelsius: current.temperature))
                        .font(Self.temperature)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(current.condition.summary)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                    ForEach(facts, id: \.self) { fact in
                        Text(fact)
                            .font(Theme.Typography.keyCap)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The lines beside the temperature, each present only when the response carried it.
    private var facts: [String] {
        let current = snapshot.forecast.current
        var lines: [String] = []
        if let feels = current.apparentTemperature {
            lines.append("Feels like \(unit.temperature(fromCelsius: feels))")
        }
        if let high = snapshot.forecast.todayHigh, let low = snapshot.forecast.todayLow {
            lines.append(
                "High \(unit.temperature(fromCelsius: high)) · Low \(unit.temperature(fromCelsius: low))"
            )
        }
        if let humidity = current.humidity {
            lines.append("Humidity \(PersonalWeatherFormat.percent(humidity))")
        }
        if let wind = current.windSpeed {
            lines.append("Wind \(unit.windSpeed(fromKilometersPerHour: wind))")
        }
        return lines
    }

    private static let glyph: CGFloat = 40
    private static let temperature = Font.system(.largeTitle, design: .rounded).weight(.semibold)
}
