import Foundation

/// The strings the Hydration tile, popover and reminder show.
enum HydrationFormat {
    /// "1,250 mL".
    static func milliliters(_ value: Int, locale: Locale) -> String {
        "\(value.formatted(.number.locale(locale))) mL"
    }

    /// "1,250 mL" or "5 drinks", whichever the progress counts.
    static func amount(_ value: Int, unit: HydrationSettings.Unit, locale: Locale) -> String {
        switch unit {
        case .milliliters: milliliters(value, locale: locale)
        case .drinks: drinks(value, locale: locale)
        }
    }

    static func drinks(_ count: Int, locale: Locale) -> String {
        let number = count.formatted(.number.locale(locale))
        return count == 1 ? "\(number) drink" : "\(number) drinks"
    }

    /// "1,250 / 2,000 mL" or "5 / 8 drinks".
    static func progress(_ progress: HydrationProgress, locale: Locale) -> String {
        let consumed = progress.consumed.formatted(.number.locale(locale))
        let goal = progress.goal.formatted(.number.locale(locale))
        switch progress.unit {
        case .milliliters: return "\(consumed) / \(goal) mL"
        case .drinks: return "\(consumed) / \(goal) drinks"
        }
    }

    /// "1,250 mL": the consumed half of `progress`, for a tile too narrow for both.
    static func consumed(_ progress: HydrationProgress, locale: Locale) -> String {
        amount(progress.consumed, unit: progress.unit, locale: locale)
    }

    /// "of 2,000 mL": the goal half, set under `consumed`.
    static func goalLine(_ progress: HydrationProgress, locale: Locale) -> String {
        "of \(amount(progress.goal, unit: progress.unit, locale: locale))"
    }

    /// A drink's own amount, or just "Drink" when the instance only counts.
    static func entry(_ entry: HydrationEntry, locale: Locale) -> String {
        entry.milliliters.map { milliliters($0, locale: locale) } ?? "Drink"
    }

    /// A drink inside a sentence: "250 mL", or "a drink" when the instance only counts.
    static func phrase(_ entry: HydrationEntry, locale: Locale) -> String {
        entry.milliliters.map { milliliters($0, locale: locale) } ?? "a drink"
    }

    /// A countdown that fits a dock tile: "<1m", "42m", "1h 05m".
    static func countdown(seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        guard minutes >= 1 else { return "<1m" }
        guard minutes >= 60 else { return "\(minutes)m" }
        let remainder = minutes % 60
        return remainder == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(String(format: "%02d", remainder))m"
    }

    /// "Today", "Yesterday", else a dated heading such as "Mon, Oct 5".
    static func dayTitle(_ start: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let today = calendar.startOfDay(for: now)
        if start == today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), start == yesterday {
            return "Yesterday"
        }
        return start.formatted(
            Date.FormatStyle(
                date: .abbreviated, time: .omitted, locale: locale, calendar: calendar,
                timeZone: calendar.timeZone)
        )
    }

    static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                timeZone: calendar.timeZone))
    }

    /// The reminder card's body: how far today is, so the nudge says what is still owed.
    static func reminderBody(_ progress: HydrationProgress, locale: Locale) -> String {
        let status = Self.progress(progress, locale: locale)
        return progress.isReached ? "Goal reached today (\(status))." : "Today so far: \(status)."
    }
}
