import Foundation

/// An app a reminder can be handed to besides Onecast's own notification; each is opt-in.
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

/// Where one reminder goes: Onecast's own notification, the apps a phrase named, or both at once.
struct ReminderTargets: Equatable, Sendable {
    var onecast: Bool
    /// In the order the phrase named them, each once.
    var apps: [ReminderApp]

    /// A phrase that names nowhere is Onecast's, as every reminder was before apps existed.
    static let onecastOnly = ReminderTargets(onecast: true, apps: [])
}

/// What the on-device model made of a phrase the parser could not read whole; no rule, no time.
struct ReminderReading: Equatable, Sendable {
    var title: String
    var rule: ScheduleRule?
    var targets: ReminderTargets
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
    @MainActor (ParsedReminder, ReminderApp) async throws(ReminderAppFailure) -> Date?

extension ReminderPhraseParser {
    /// Lifts "add it to Things", "put this in Apple Reminders and Onecast" or "in the Things app" out
    /// of the phrase. It needs a cue, like a colour: "sort the things in the attic" stays whole.
    static func splittingTargets(_ text: String) -> (targets: ReminderTargets, request: String) {
        let whole = NSRange(text.startIndex..., in: text)
        for pattern in targetPatterns {
            guard let match = pattern.firstMatch(in: text, range: whole),
                let range = Range(match.range, in: text)
            else { continue }
            let cue = String(text[range])
            var targets = ReminderTargets(onecast: false, apps: [])
            for name in appName?.matches(in: cue, range: NSRange(cue.startIndex..., in: cue)) ?? [] {
                guard let nameRange = Range(name.range, in: cue) else { continue }
                let word = cue[nameRange].lowercased()
                if word.contains("cast") {
                    targets.onecast = true
                } else {
                    let app: ReminderApp = word.hasPrefix("th") ? .things : .appleReminders
                    if !targets.apps.contains(app) { targets.apps.append(app) }
                }
            }
            return (targets, text.replacingCharacters(in: range, with: " "))
        }
        return (.onecastOnly, text)
    }

    /// "ad it tp thigns": it asks to send the reminder somewhere no cue could name; the model reads it.
    static func asksForATarget(_ text: String) -> Bool {
        attempt?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let attempt = try? NSRegularExpression(
        pattern: #"\b(?:add|ad|put|save|send|log)\s+(?:it|this|that|them)\b"#, options: [.caseInsensitive])

    /// Loose on purpose, since these are typed fast: "reminder", "remiders", "thngs", "one cast".
    private static let appSource =
        #"(?:th(?:in?|n)gs?(?:\s*3)?|(?:apple(?:'s|s)?\s+)?rem[a-z]{0,3}ders?|one\s*cast)"#

    private static let appName = try? NSRegularExpression(pattern: appSource, options: [.caseInsensitive])

    /// A verb before a list of apps, or a bare preposition before a list ending in "app".
    private static let targetPatterns: [NSRegularExpression] = {
        let item = #"(?:the\s+|my\s+)?"# + appSource + #"(?:\s+apps?)?"#
        let joiner = #"(?:\s*,\s*(?:and\s+)?|\s+(?:and|&|plus|as\s+well\s+as)\s+)(?:(?:to|in|into|on)\s+)?"#
        let list = item + "(?:" + joiner + item + ")*" + #"(?:\s+(?:too|as\s+well|both))?\b"#
        let lead = #"[,;]?\s*\b(?:and\s+)?(?:also\s+)?"#
        // A short connector is taken whatever it is, so "add it tp things" still reads as a cue.
        let sources = [
            lead + #"(?:add|put|save|send|create|log|make)\s+(?:(?:it|this|that|them)\s+)?"#
                + #"(?:(?:as\s+)?an?\s+(?:reminder|to-?do|task)\s+)?(?:into|onto|[a-z]{1,2})\s+"# + list,
            lead + #"(?:in|to|into|on|via|using)\s+"# + list + #"(?<=apps?)\b"#,
            lead + #"(?:in|to|into|on|via|using)\s+(?:the\s+|my\s+)?apple(?:'s|s)?\s+reminders?\b"#,
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()
}

/// Things' URL scheme, which adds a to-do without an auth token and, with a time, reminds at it.
enum ThingsURL {
    /// No time leaves the to-do in the Inbox. Things keeps minutes only, so a seconds tail rounds
    /// up: a reminder is late by seconds, never early.
    static func add(title: String, at date: Date?, calendar: Calendar) -> URL? {
        guard let date else { return URL(string: "things:///add?title=\(encode(title))") }
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
