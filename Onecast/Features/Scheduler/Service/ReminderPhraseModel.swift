import FoundationModels
import Foundation

/// On-device reading of a phrase the parser could not read whole: title, time and apps, typos too.
enum ReminderPhraseModel {
    static func read(_ text: String, now: Date, calendar: Calendar) async -> ReminderReading? {
        guard AppleIntelligenceProvider.status().isAvailable else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        let prompt =
            "The current date and time is \(anchorFormatter.string(from: now)). "
            + "Convert this reminder request into the fields: \"\(text)\""
        guard let extracted = try? await session.respond(
            to: prompt, generating: ExtractedReminder.self).content
        else { return nil }
        return reading(from: extracted, now: now, calendar: calendar)
    }

    private static func reading(
        from extracted: ExtractedReminder, now: Date, calendar: Calendar
    ) -> ReminderReading? {
        let title = extracted.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var apps: [ReminderApp] = []
        if extracted.addToAppleReminders { apps.append(.appleReminders) }
        if extracted.addToThings { apps.append(.things) }
        // Naming no app at all is a Onecast reminder, as a phrase with no cue always was.
        let targets = ReminderTargets(onecast: extracted.keepInOnecast || apps.isEmpty, apps: apps)
        guard extracted.namesATime else { return ReminderReading(title: title, rule: nil, targets: targets) }
        guard let rule = rule(from: extracted, now: now, calendar: calendar) else { return nil }
        return ReminderReading(title: title, rule: rule, targets: targets)
    }

    private static func rule(
        from extracted: ExtractedReminder, now: Date, calendar: Calendar
    ) -> ScheduleRule? {
        guard let date = date(from: extracted.when) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 9, minute = parts.minute ?? 0
        switch extracted.repeats.lowercased() {
        case "daily":
            return .daily(hour: hour, minute: minute)
        case "weekly":
            return .weekly(weekdays: [calendar.component(.weekday, from: date)], hour: hour, minute: minute)
        case "monthly":
            return .monthly(day: calendar.component(.day, from: date), hour: hour, minute: minute)
        default:
            return date > now ? .once(date) : nil
        }
    }

    /// The model's `when` may or may not carry an offset or seconds, so several shapes are tried.
    private static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in dateParsers {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    private static let instructions =
        "You turn a reminder request into structured fields. `namesATime` is true only when the "
        + "request itself states a time, date or delay; otherwise it is false and `when` is ignored. "
        + "`title` is a concise imperative with no time or date words and no mention of which app "
        + "keeps it. `when` is the first fire time as an ISO 8601 date-time in the future, e.g. "
        + "2026-01-31T14:00:00. Set `repeats` to none unless the request explicitly recurs; use daily, "
        + "weekly or monthly only when it clearly repeats. The request may ask to put the reminder in "
        + "Apple Reminders (also called Reminders), Things, or Onecast, and is often typed fast: read "
        + "misspellings like 'tp' for 'to', 'thigns' for 'Things' or 'remindrs' for 'Reminders'."

    private static let anchorFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ (EEEE)"
        return formatter
    }()

    private static let dateParsers: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter
        }
    }()
}

@Generable
private struct ExtractedReminder {
    /// First, so the model commits to whether a time exists before it is asked to write one.
    @Guide(description: "True only if the request states a time, date or delay")
    var namesATime: Bool
    @Guide(description: "A concise imperative title with no time or date words, e.g. Book the ticket")
    var title: String
    @Guide(description: "The first fire time as an ISO 8601 date-time in the future")
    var when: String
    @Guide(description: "How often it repeats", .anyOf(["none", "daily", "weekly", "monthly"]))
    var repeats: String
    @Guide(description: "True if the request asks for a Onecast reminder or notification")
    var keepInOnecast: Bool
    @Guide(description: "True if the request asks to add it to Apple Reminders, even misspelled")
    var addToAppleReminders: Bool
    @Guide(description: "True if the request asks to add it to the Things app, even misspelled")
    var addToThings: Bool
}
