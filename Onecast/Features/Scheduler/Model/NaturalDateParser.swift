import Foundation

/// Free-text "when" parsing for one-shot tasks. Absolute phrases ("tomorrow at 9am") come from
/// `NSDataDetector`; relative durations ("in 20 minutes") are its blind spot, so they are matched
/// first. Each hit carries the span it matched, so a caller can lift the time out of a longer
/// sentence and keep the rest as a title.
enum NaturalDateParser {
    struct Match {
        let date: Date
        let range: Range<String.Index>
    }

    static func date(from text: String, now: Date, calendar: Calendar) -> Date? {
        match(in: normalizingClock(text), now: now, calendar: calendar)?.date
    }

    /// "9:am", "9 : 30 pm", "9.30 a.m." read as the clock times they mean; `NSDataDetector` misses
    /// them. A caller lifting a match out must normalise first, so the match's range stays its own.
    static func normalizingClock(_ text: String) -> String {
        clockRewrites.reduce(text) { result, rewrite in
            rewrite.pattern.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: rewrite.template)
        }
    }

    private static let clockRewrites: [(pattern: NSRegularExpression, template: String)] = [
        (#"\b([ap])\.m\.?(?=\s|$|[,;!?])"#, "$1m"),
        (#"\b(\d{1,2})\s*[:.]\s*(\d{2})\s*([ap]m)\b"#, "$1:$2 $3"),
        (#"\b(\d{1,2})\s*[:.]\s*([ap]m)\b"#, "$1 $2"),
        (#"\b(\d{1,2})\s+:\s*(\d{2})\b"#, "$1:$2"),
    ].compactMap { source, template in
        (try? NSRegularExpression(pattern: source, options: [.caseInsensitive])).map { ($0, template) }
    }

    /// Relative first — `NSDataDetector` resolves none of the "in N units" forms — then absolute.
    static func match(in text: String, now: Date, calendar: Calendar) -> Match? {
        relativeMatch(in: text, now: now, calendar: calendar)
            ?? absoluteMatch(in: text, now: now, calendar: calendar)
    }

    private static func relativeMatch(in text: String, now: Date, calendar: Calendar) -> Match? {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        for expression in relativeExpressions {
            guard let result = expression.firstMatch(in: text, options: [], range: full),
                let range = Range(result.range, in: text),
                let countRange = Range(result.range(at: 1), in: text),
                let unitRange = Range(result.range(at: 2), in: text),
                let amount = number(String(text[countRange])),
                let component = component(for: String(text[unitRange])),
                let date = calendar.date(byAdding: component, value: amount, to: now)
            else { continue }
            return Match(date: date, range: range)
        }
        return nil
    }

    private static func absoluteMatch(in text: String, now: Date, calendar: Calendar) -> Match? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return nil }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = detector.firstMatch(in: text, options: [], range: full),
            let detected = result.date, let range = Range(result.range, in: text)
        else { return nil }
        // NSDataDetector resolves "tomorrow" et al. against the live clock; re-anchor onto `now`.
        let driftDays = calendar.dateComponents([.day], from: Date(), to: now).day ?? 0
        var anchored = calendar.date(byAdding: .day, value: driftDays, to: detected) ?? detected
        // A bare clock time already past today means its next one: "at 9am" said at noon is tomorrow.
        if anchored <= now, !namesADay(String(text[range])) {
            anchored = calendar.date(byAdding: .day, value: 1, to: anchored) ?? anchored
        }
        return Match(date: anchored, range: range)
    }

    private static func namesADay(_ phrase: String) -> Bool {
        dayWords?.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)) != nil
    }

    private static let dayWords = try? NSRegularExpression(
        pattern: #"\b(?:today|tonight|tomorrow|yesterday|mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|"#
            + #"may|jun|jul|aug|sep|oct|nov|dec|next|this|\d{1,2}(?:st|nd|rd|th)|\d{1,4}[/-]\d{1,2})"#,
        options: [.caseInsensitive])

    private static func number(_ token: String) -> Int? {
        if let value = Int(token) { return value }
        return words[token.lowercased()]
    }

    private static func component(for unit: String) -> Calendar.Component? {
        switch unit.lowercased() {
        case let u where u.hasPrefix("sec"): return .second
        case let u where u.hasPrefix("min"): return .minute
        case let u where u.hasPrefix("hr") || u.hasPrefix("hour"): return .hour
        case let u where u.hasPrefix("day"): return .day
        case let u where u.hasPrefix("week"): return .weekOfYear
        case let u where u.hasPrefix("month"): return .month
        default: return nil
        }
    }

    private static let words: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]

    /// Group 1 is the count (digits or a number word), group 2 the unit; both spellings covered.
    private static let relativeExpressions: [NSRegularExpression] = {
        let count = #"(\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten)"#
        let unit = #"(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?)"#
        let patterns = [
            #"\b(?:in|after|within)\s+(?:the\s+)?(?:next\s+)?"# + count + #"\s*"# + unit + #"\b"#,
            #"\b"# + count + #"\s*"# + unit + #"\s+(?:from\s+now|later)\b"#,
        ]
        return patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()
}
