import Foundation

/// An ISO 8601 instant as the tools write it, read without a formatter so a scan stays cheap.
enum PersonalAIUsageTimestamp {
    /// Seconds since 1970; nil unless it is `YYYY-MM-DDTHH:MM:SS[.fff]` plus `Z` or an offset.
    static func parse(_ text: String) -> TimeInterval? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 20, bytes[4] == dash, bytes[7] == dash, bytes[10] == upperT,
            bytes[13] == colon, bytes[16] == colon,
            let year = number(bytes, 0, 4), let month = number(bytes, 5, 2),
            let day = number(bytes, 8, 2), let hour = number(bytes, 11, 2),
            let minute = number(bytes, 14, 2), let second = number(bytes, 17, 2),
            (1970...9999).contains(year), (1...12).contains(month),
            (1...daysInMonth(year, month)).contains(day), hour < 24, minute < 60, second <= 60
        else { return nil }

        var index = 19
        var fraction = 0.0
        if bytes[index] == dot {
            var scale = 0.1
            index += 1
            let digitsStart = index
            while index < bytes.count, let digit = digitValue(bytes[index]) {
                fraction += Double(digit) * scale
                scale /= 10
                index += 1
            }
            guard index > digitsStart else { return nil }
        }
        guard index < bytes.count, let offset = zoneOffset(bytes, from: index) else { return nil }
        let days = daysFromCivil(year, month, day)
        return TimeInterval(days * 86_400 + hour * 3_600 + minute * 60 + second - offset) + fraction
    }

    private static let dash = UInt8(ascii: "-")
    private static let colon = UInt8(ascii: ":")
    private static let dot = UInt8(ascii: ".")
    private static let upperT = UInt8(ascii: "T")
    private static let upperZ = UInt8(ascii: "Z")
    private static let plus = UInt8(ascii: "+")

    private static func digitValue(_ byte: UInt8) -> Int? {
        (48...57).contains(byte) ? Int(byte) - 48 : nil
    }

    private static func number(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int? {
        var value = 0
        for byte in bytes[start..<start + count] {
            guard let digit = digitValue(byte) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    /// Seconds east of UTC for `Z`, `+05:30`, `+0530` or `+05`; nil for anything after it.
    private static func zoneOffset(_ bytes: [UInt8], from start: Int) -> Int? {
        if bytes[start] == upperZ { return start + 1 == bytes.count ? 0 : nil }
        guard bytes[start] == plus || bytes[start] == dash else { return nil }
        let sign = bytes[start] == plus ? 1 : -1
        let rest = bytes.count - start - 1
        guard [2, 4, 5].contains(rest), let hours = number(bytes, start + 1, 2), hours < 24 else {
            return nil
        }
        var minutes = 0
        if rest > 2 {
            let minuteStart = start + (rest == 5 ? 4 : 3)
            if rest == 5, bytes[start + 3] != colon { return nil }
            guard let parsed = number(bytes, minuteStart, 2), parsed < 60 else { return nil }
            minutes = parsed
        }
        return sign * (hours * 3_600 + minutes * 60)
    }

    private static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Hinnant's algorithm).
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = shiftedYear / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

/// A Codex `token_count` event: running totals since its session began, not one turn's use.
struct PersonalAIUsageCodexSample: Sendable, Equatable {
    struct Totals: Sendable, Equatable {
        var input = 0
        /// A subset of `input`: what the prompt cache served.
        var cachedInput = 0
        var output = 0

        /// What was added since `previous`; a counter that fell restarted, so it is all new.
        func growth(since previous: Totals) -> Totals {
            Totals(
                input: Self.step(input, previous.input),
                cachedInput: Self.step(cachedInput, previous.cachedInput),
                output: Self.step(output, previous.output))
        }

        /// Uncached input and output are the headline; the cached share is detail.
        var tokens: PersonalAIUsageTokens {
            let cached = min(cachedInput, input)
            return PersonalAIUsageTokens(input: input - cached, output: output, cache: cached)
        }

        private static func step(_ current: Int, _ previous: Int) -> Int {
            current >= previous ? current - previous : current
        }
    }

    let time: TimeInterval
    let totals: Totals
}

/// Reads single log lines; anything it cannot trust is nil, so one bad line costs only itself.
enum PersonalAIUsageLogParser {
    /// Past this a count is corrupt; the cap keeps one bad field from overflowing a sum.
    static let maxCount = 1_000_000_000_000

    private static let usageNeedle = Data(#""usage""#.utf8)
    private static let assistantNeedle = Data(#""assistant""#.utf8)
    private static let tokenCountNeedle = Data(#""token_count""#.utf8)

    /// A Claude Code assistant turn's own usage: input and output, with cache counted aside.
    static func claudeEntry(_ line: Data) -> PersonalAIUsageEntry? {
        guard contains(usageNeedle, in: line), contains(assistantNeedle, in: line),
            let record = try? JSONDecoder().decode(ClaudeLine.self, from: line),
            (record.type ?? record.message?.role) == "assistant",
            let usage = record.message?.usage, usage.hasCounts,
            let time = record.timestamp.flatMap(PersonalAIUsageTimestamp.parse)
        else { return nil }
        let tokens = PersonalAIUsageTokens(
            input: clamp(usage.input), output: clamp(usage.output),
            cache: clamp(usage.cacheRead) + clamp(usage.cacheCreation))
        guard !tokens.isZero else { return nil }
        let key = record.message?.id.map { "\($0)|\(record.requestID ?? "")" }
        return PersonalAIUsageEntry(key: key, time: time, tokens: tokens)
    }

    static func codexSample(_ line: Data) -> PersonalAIUsageCodexSample? {
        guard contains(tokenCountNeedle, in: line),
            let record = try? JSONDecoder().decode(CodexLine.self, from: line),
            record.payload?.type == "token_count",
            let usage = record.payload?.info?.totalTokenUsage, usage.hasCounts,
            let time = record.timestamp.flatMap(PersonalAIUsageTimestamp.parse)
        else { return nil }
        return PersonalAIUsageCodexSample(
            time: time,
            totals: PersonalAIUsageCodexSample.Totals(
                input: clamp(usage.input), cachedInput: clamp(usage.cachedInput),
                output: clamp(usage.output)))
    }

    private static func clamp(_ value: Int?) -> Int {
        min(max(value ?? 0, 0), maxCount)
    }

    /// Most lines are neither; a byte search settles that before any JSON is parsed.
    private static func contains(_ needle: Data, in line: Data) -> Bool {
        line.withUnsafeBytes { haystack in
            needle.withUnsafeBytes { pattern in
                guard let start = haystack.baseAddress, let target = pattern.baseAddress else {
                    return false
                }
                return memmem(start, haystack.count, target, pattern.count) != nil
            }
        }
    }
}

/// A log reader fed one line at a time; `entries` is what the lines so far were worth.
protocol PersonalAIUsageLogParsing: Sendable {
    init()
    var entries: [PersonalAIUsageEntry] { get }
    mutating func consume(_ line: Data)
}

struct PersonalAIUsageClaudeLog: PersonalAIUsageLogParsing {
    private var deduper = PersonalAIUsageDeduper()

    var entries: [PersonalAIUsageEntry] { deduper.entries }

    mutating func consume(_ line: Data) {
        guard let entry = PersonalAIUsageLogParser.claudeEntry(line) else { return }
        deduper.add(entry)
    }
}

/// Turns Codex's running totals into per-event growth, so a repeated event adds nothing.
struct PersonalAIUsageCodexLog: PersonalAIUsageLogParsing {
    private(set) var entries: [PersonalAIUsageEntry] = []
    private var previous: PersonalAIUsageCodexSample.Totals?

    mutating func consume(_ line: Data) {
        guard let sample = PersonalAIUsageLogParser.codexSample(line) else { return }
        let growth = previous.map { sample.totals.growth(since: $0) } ?? sample.totals
        previous = sample.totals
        let tokens = growth.tokens
        guard !tokens.isZero else { return }
        entries.append(PersonalAIUsageEntry(key: nil, time: sample.time, tokens: tokens))
    }
}

// MARK: - Decoding

/// A count that is a number or nothing: a string, null or overflowing value reads as absent.
private struct LenientCount: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let whole = try? container.decode(Int.self) {
            value = whole
        } else if let real = try? container.decode(Double.self) {
            value = Int(exactly: real)
        } else {
            value = nil
        }
    }
}

private struct ClaudeLine: Decodable {
    let type: String?
    let timestamp: String?
    let requestID: String?
    let message: Message?

    struct Message: Decodable {
        let id: String?
        let role: String?
        let usage: Usage?

        private enum CodingKeys: String, CodingKey { case id, role, usage }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decode(String.self, forKey: .id)
            role = try? container.decode(String.self, forKey: .role)
            usage = try? container.decode(Usage.self, forKey: .usage)
        }
    }

    struct Usage: Decodable {
        let input: Int?
        let output: Int?
        let cacheRead: Int?
        let cacheCreation: Int?

        var hasCounts: Bool { input != nil || output != nil }

        private enum CodingKeys: String, CodingKey {
            case input = "input_tokens"
            case output = "output_tokens"
            case cacheRead = "cache_read_input_tokens"
            case cacheCreation = "cache_creation_input_tokens"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = (try? container.decode(LenientCount.self, forKey: .input))?.value
            output = (try? container.decode(LenientCount.self, forKey: .output))?.value
            cacheRead = (try? container.decode(LenientCount.self, forKey: .cacheRead))?.value
            cacheCreation =
                (try? container.decode(LenientCount.self, forKey: .cacheCreation))?.value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, timestamp, message
        case requestID = "requestId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decode(String.self, forKey: .type)
        timestamp = try? container.decode(String.self, forKey: .timestamp)
        requestID = try? container.decode(String.self, forKey: .requestID)
        message = try? container.decode(Message.self, forKey: .message)
    }
}

private struct CodexLine: Decodable {
    let timestamp: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?
        let info: Info?

        private enum CodingKeys: String, CodingKey { case type, info }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try? container.decode(String.self, forKey: .type)
            info = try? container.decode(Info.self, forKey: .info)
        }
    }

    struct Info: Decodable {
        let totalTokenUsage: Usage?

        private enum CodingKeys: String, CodingKey { case totalTokenUsage = "total_token_usage" }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalTokenUsage = try? container.decode(Usage.self, forKey: .totalTokenUsage)
        }
    }

    struct Usage: Decodable {
        let input: Int?
        let cachedInput: Int?
        let output: Int?

        var hasCounts: Bool { input != nil || output != nil }

        private enum CodingKeys: String, CodingKey {
            case input = "input_tokens"
            case cachedInput = "cached_input_tokens"
            case output = "output_tokens"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = (try? container.decode(LenientCount.self, forKey: .input))?.value
            cachedInput = (try? container.decode(LenientCount.self, forKey: .cachedInput))?.value
            output = (try? container.decode(LenientCount.self, forKey: .output))?.value
        }
    }

    private enum CodingKeys: String, CodingKey { case timestamp, payload }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try? container.decode(String.self, forKey: .timestamp)
        payload = try? container.decode(Payload.self, forKey: .payload)
    }
}
