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

/// Where a reminder goes when its phrase names nowhere: Onecast itself, or one of the apps.
enum ReminderPlace: String, CaseIterable, Codable, Sendable, Identifiable {
    case onecast
    case appleReminders
    case things

    var id: String { rawValue }

    var app: ReminderApp? { ReminderApp(rawValue: rawValue) }

    var title: String { app?.title ?? "Onecast" }
}

/// Where one reminder goes: Onecast's own notification, the apps a phrase named, or both at once.
struct ReminderTargets: Equatable, Sendable {
    var onecast: Bool
    /// In the order the phrase named them, each once.
    var apps: [ReminderApp]

    static let onecastOnly = ReminderTargets(onecast: true, apps: [])

    /// A phrase that names nowhere, which the default reminder app takes.
    static let unnamed = ReminderTargets(onecast: false, apps: [])

    /// Named apps left off drop out; naming nowhere, or only those, falls to the default, and to
    /// Onecast when the default is off or can't hold the rule.
    func resolved(
        enabled: Set<ReminderApp>, default place: ReminderPlace, rule: ScheduleRule?
    ) -> ReminderTargets {
        let kept = apps.filter(enabled.contains)
        if onecast || !kept.isEmpty { return ReminderTargets(onecast: onecast, apps: kept) }
        guard let app = place.app, enabled.contains(app), rule.flatMap(app.refusal(of:)) == nil
        else { return .onecastOnly }
        return ReminderTargets(onecast: false, apps: [app])
    }
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

/// Settles where the user named against Settings' apps and default, as `resolved` does.
typealias ReminderRoute = @MainActor (ReminderTargets, ScheduleRule?) -> ReminderTargets

extension ReminderPhraseParser {
    /// Lifts "…, save it to reminders nad things" out; a list needs a cue, so "check my reminders" stays.
    static func splittingTargets(_ text: String) -> (targets: ReminderTargets, request: String) {
        let words = TargetWords(text)
        let spans = words.targetSpans()
        guard !spans.isEmpty else { return (.unnamed, text) }
        var request = text
        for span in spans.reversed() { request.replaceSubrange(words.range(of: span), with: " ") }
        return (words.targets(in: spans), request)
    }

    /// Every place the phrase names at all, cue or not: a model's reading may only choose among them.
    static func mentionedTargets(_ text: String) -> ReminderTargets {
        let words = TargetWords(text)
        return words.targets(in: words.roles.isEmpty ? [] : [0...(words.roles.count - 1)])
    }

    /// A cue just before an app name that no list could be read from: the model reads the phrase.
    static func asksForATarget(_ text: String) -> Bool {
        let roles = TargetWords(text).roles
        return roles.indices.contains { index in
            guard case .app = roles[index] else { return false }
            return roles[max(0, index - 3)..<index].contains(where: \.isCue)
        }
    }
}

/// A phrase read word by word: an app, a verb or preposition that sends, glue, a break, or the errand.
private struct TargetWords {
    enum Place: Equatable { case onecast, app(ReminderApp) }
    enum Role: Equatable {
        case app(Place), verb, preposition, glue, separator, other

        var isCue: Bool { self == .verb || self == .preposition }
        var isApp: Bool { if case .app = self { true } else { false } }
    }

    let ranges: [Range<String.Index>]
    let roles: [Role]

    init(_ text: String) {
        let found = (Self.token?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [])
            .compactMap { Range($0.range, in: text) }
        ranges = found
        roles = Self.roles(of: found.map { text[$0].lowercased() })
    }

    func range(of span: ClosedRange<Int>) -> Range<String.Index> {
        ranges[span.lowerBound].lowerBound..<ranges[span.upperBound].upperBound
    }

    func targets(in spans: [ClosedRange<Int>]) -> ReminderTargets {
        var targets = ReminderTargets(onecast: false, apps: [])
        for index in spans.flatMap({ Array($0) }) {
            switch roles[index] {
            case .app(.onecast): targets.onecast = true
            case .app(.app(let app)) where !targets.apps.contains(app): targets.apps.append(app)
            default: break
            }
        }
        return targets
    }

    /// The phrase's closing run, a clause of only these words, or a place mid-clause, each with a cue.
    func targetSpans() -> [ClosedRange<Int>] {
        guard !roles.isEmpty else { return [] }
        var spans: [ClosedRange<Int>] = []
        let tailStart = (roles.lastIndex(of: .other) ?? -1) + 1
        if tailStart < roles.count { spans.append(tailStart...(roles.count - 1)) }
        var start = 0
        for index in 0...roles.count where index == roles.count || roles[index] == .separator {
            if start < index, index - 1 < tailStart, !roles[start..<index].contains(.other) {
                spans.append(start...(index - 1))
            }
            start = index + 1
        }
        spans = spans.filter { roles[$0].contains(where: \.isCue) && roles[$0].contains(where: \.isApp) }
        for index in roles.indices where roles[index].isApp && !spans.contains(where: { $0.contains(index) }) {
            if let span = placeInClause(at: index), !spans.contains(where: { $0.overlaps(span) }) {
                spans.append(span)
            }
        }
        return spans.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// "add milk to things at 5pm": a preposition before the app and a sending verb within reach.
    private func placeInClause(at app: Int) -> ClosedRange<Int>? {
        var before = app - 1
        while before >= 0, roles[before] == .glue || roles[before].isApp { before -= 1 }
        guard before >= 0, roles[before] == .preposition else { return nil }
        var start = before
        while start > 0, ![.other, .separator].contains(roles[start - 1]) { start -= 1 }
        var end = app
        while end + 1 < roles.count, roles[end + 1] == .glue || roles[end + 1].isApp { end += 1 }
        guard roles[max(0, start - 3)...before].contains(.verb) else { return nil }
        return start...end
    }

    private static let token = try? NSRegularExpression(
        pattern: #"[a-z0-9'][a-z0-9'-]*|[,;.!?&+]"#, options: [.caseInsensitive])

    private static func roles(of words: [String]) -> [Role] {
        var roles: [Role] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let next = index + 1 < words.count ? words[index + 1] : ""
            let previous = roles.isEmpty ? "" : words[index - 1]
            if word.count == 1, ",;.!?".contains(word) {
                roles.append(.separator)
            } else if near(word, "apple") || near(word, "apples"),
                near(next, "reminders") || near(next, "reminder")
            {
                roles += [.app(.app(.appleReminders)), .glue]
                index += 2
                continue
            } else if near(word, "reminders") || near(word, "reminder"),
                // "set a reminder" is the reminder itself, not the Reminders app.
                !["a", "an", "as"].contains(previous)
            {
                roles.append(.app(.app(.appleReminders)))
            } else if word != "thing", near(word, "things") {
                roles.append(.app(.app(.things)))
                if next == "3" {
                    roles.append(.glue)
                    index += 2
                    continue
                }
            } else if near(word, "onecast") {
                roles.append(.app(.onecast))
            } else if word == "one", near(next, "cast") {
                roles += [.app(.onecast), .glue]
                index += 2
                continue
            } else {
                roles.append(role(of: word))
            }
            index += 1
        }
        return roles
    }

    /// An exact word first, so "and" is never a mistyped "add"; only then the nearest spelling.
    private static func role(of word: String) -> Role {
        if verbs.contains(word) { return .verb }
        if prepositions.contains(word) { return .preposition }
        if glue.contains(word) { return .glue }
        if glue.contains(where: { near(word, $0) }) { return .glue }
        if verbs.contains(where: { near(word, $0) }) { return .verb }
        if prepositions.contains(where: { near(word, $0) }) { return .preposition }
        return .other
    }

    private static let verbs: Set<String> = [
        "add", "ad", "put", "save", "send", "log", "create", "make", "set", "keep", "store", "push",
        "copy", "file", "track", "schedule",
    ]

    private static let prepositions: Set<String> = ["to", "in", "into", "on", "onto", "via", "using", "inside"]

    private static let glue: Set<String> = [
        "and", "or", "plus", "&", "+", "also", "the", "my", "it", "this", "that", "them", "these",
        "those", "app", "apps", "application", "both", "all", "too", "as", "well", "please", "pls",
        "a", "an", "reminder", "to-do", "todo", "task", "list", "inbox",
    ]

    /// One slip, swaps included, from three letters up; a two-letter word may only be a mistyped "to".
    private static func near(_ word: String, _ target: String) -> Bool {
        if word == target { return true }
        guard word.count >= 3 && target.count >= 3 || target == "to" && word.count == 2 else {
            return false
        }
        return abs(word.count - target.count) <= 1 && editDistance(word, target) <= 1
    }

    /// Optimal string alignment distance, which counts a transposition ("adn") as one edit.
    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in stride(from: 1, through: a.count, by: 1) {
            for j in stride(from: 1, through: b.count, by: 1) {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
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
