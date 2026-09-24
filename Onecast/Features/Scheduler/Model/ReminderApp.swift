import Foundation

/// An app a reminder can be handed to instead of Onecast's own notification; each is opt-in.
enum ReminderApp: String, CaseIterable, Codable, Sendable, Identifiable {
    case appleReminders
    case things

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleReminders: "Apple Reminders"
        case .things: "Things"
        }
    }

    /// Why this app cannot hold `rule`, or nil when it can: neither takes an every-N-minutes repeat,
    /// and Things' URL scheme cannot make a to-do repeat at all.
    func refusal(of rule: ScheduleRule) -> String? {
        switch (self, rule) {
        case (_, .once), (.appleReminders, .daily), (.appleReminders, .weekly),
            (.appleReminders, .monthly):
            nil
        case (.appleReminders, .interval):
            "Apple Reminders can't repeat every few minutes or hours. Keep this one in Onecast."
        case (.things, _):
            "Things can't take a repeating reminder from another app. Keep this one in Onecast."
        }
    }

    /// When the reminder first goes off, which is the due date the app is given.
    static func firstFire(of rule: ScheduleRule, now: Date, calendar: Calendar) -> Date? {
        let task = ScheduledTask.notification(title: "", rule: rule, tint: nil, now: now)
        return ScheduleEngine.nextFireDate(for: task, after: now, calendar: calendar)
    }
}

/// Why an app would not take a reminder, worded for the reader.
struct ReminderAppFailure: Error, Equatable {
    let message: String

    static func notEnabled(_ app: ReminderApp) -> Self {
        Self(message: "Turn on \(app.title) in Settings → Scheduler to add reminders there.")
    }
}

/// Gives a reminder to an app and says when it is due; the chat supplies Settings' consent with it.
typealias ReminderHandOff =
    @MainActor (ParsedReminder, ReminderApp) async throws(ReminderAppFailure) -> Date

extension ReminderPhraseParser {
    /// Lifts "add it to Things", "put this in Apple Reminders" or "in the Things app" out of the
    /// phrase. It needs a cue, like a colour: "remind me to sort the things in the attic" stays whole.
    static func splittingApp(_ text: String) -> (app: ReminderApp?, request: String) {
        let whole = NSRange(text.startIndex..., in: text)
        for pattern in appPatterns {
            guard let match = pattern.firstMatch(in: text, range: whole),
                let range = Range(match.range, in: text)
            else { continue }
            let app: ReminderApp = text[range].lowercased().contains("thing") ? .things : .appleReminders
            return (app, text.replacingCharacters(in: range, with: " "))
        }
        return (nil, text)
    }

    /// A verb naming either app anywhere, or a bare preposition before an unmistakable app name.
    private static let appPatterns: [NSRegularExpression] = {
        let app = #"(?:things(?:\s*3)?|(?:apple(?:'s|s)?\s+)?reminders?)"#
        let lead = #"[,;]?\s*\b(?:and\s+)?"#
        let place = #"(?:the\s+|my\s+)?"#
        let sources = [
            lead + #"(?:add|put|save|send|create|log|make)\s+(?:(?:it|this|that|them)\s+)?"#
                + #"(?:(?:as\s+)?an?\s+(?:reminder|to-?do|task)\s+)?(?:to|in|into|on)\s+"# + place
                + app + #"(?:\s+app)?\b"#,
            lead + #"(?:in|to|into|on|via|using)\s+"# + place + app + #"\s+app\b"#,
            lead + #"(?:in|to|into|on|via|using)\s+"# + place + #"apple(?:'s|s)?\s+reminders?\b"#,
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()
}

/// Things' URL scheme, which adds a to-do without an auth token and, with a time, reminds at it.
enum ThingsURL {
    /// Things keeps minutes only, so a seconds tail rounds up: a reminder is late by seconds, not early.
    static func add(title: String, at date: Date, calendar: Calendar) -> URL? {
        let whole = calendar.date(bySetting: .second, value: 0, of: date).map {
            $0 < date ? calendar.date(byAdding: .minute, value: 1, to: $0) ?? $0 : $0
        } ?? date
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: whole)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
            let hour = parts.hour, let minute = parts.minute
        else { return nil }
        let when = String(format: "%04d-%02d-%02d@%02d:%02d", year, month, day, hour, minute)
        return URL(string: "things:///add?title=\(encode(title))&when=\(encode(when))")
    }

    /// Only unreserved characters pass: Things decodes `+` as a space and `&` would end the title.
    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
