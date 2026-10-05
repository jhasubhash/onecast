import Foundation

/// Weather text that depends on a clock, a zone or a locale, all of them passed in.
enum PersonalWeatherFormat {
    /// "3 PM", in the zone the forecast is for, not the Mac's.
    static func hour(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(
            date: .omitted, time: .omitted, locale: locale, calendar: locale.calendar,
            timeZone: timeZone
        ).hour()
        return date.formatted(style)
    }

    static func updated(_ fetchedAt: Date, now: Date, locale: Locale = .current) -> String {
        guard now.timeIntervalSince(fetchedAt) >= justNowSeconds else { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return "Updated " + formatter.localizedString(for: fetchedAt, relativeTo: now)
    }

    /// Humidity and chance of rain, both whole percents.
    static func percent(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.number.grouping(.never).locale(locale)) + "%"
    }

    private static let justNowSeconds: TimeInterval = 60
}
