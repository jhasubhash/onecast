import Foundation

/// Input and output are the headline; cache is a detail and never joins `total`.
struct PersonalAIUsageTokens: Sendable, Equatable {
    var input = 0
    var output = 0
    var cache = 0

    static let zero = PersonalAIUsageTokens()

    var total: Int { input + output }
    var isZero: Bool { input == 0 && output == 0 && cache == 0 }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output,
            cache: lhs.cache + rhs.cache)
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    func fieldwiseMax(_ other: Self) -> Self {
        Self(
            input: max(input, other.input), output: max(output, other.output),
            cache: max(cache, other.cache))
    }
}

enum PersonalAIUsageProvider: String, Sendable, CaseIterable, Identifiable {
    case claudeCode
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Where its logs live under the home directory, for the empty-state hint.
    var logFolder: String {
        switch self {
        case .claudeCode: "~/.claude/projects"
        case .codex: "~/.codex/sessions"
        }
    }
}

/// One billed turn from a log: when it happened and what it used.
struct PersonalAIUsageEntry: Sendable, Equatable {
    /// Names one streamed message across its duplicate lines and files; nil is never merged.
    let key: String?
    /// Seconds since 1970, UTC; bucketed into local days only when summarised.
    let time: TimeInterval
    let tokens: PersonalAIUsageTokens
}

/// Counts each message once: streamed turns log per block, and resumed sessions copy old turns.
struct PersonalAIUsageDeduper: Sendable {
    private(set) var entries: [PersonalAIUsageEntry] = []
    private var indexByKey: [String: Int] = [:]

    mutating func add(_ entry: PersonalAIUsageEntry) {
        guard let key = entry.key else {
            entries.append(entry)
            return
        }
        guard let index = indexByKey[key] else {
            indexByKey[key] = entries.count
            entries.append(entry)
            return
        }
        let known = entries[index]
        entries[index] = PersonalAIUsageEntry(
            key: key, time: min(known.time, entry.time),
            tokens: known.tokens.fieldwiseMax(entry.tokens))
    }

    mutating func add(contentsOf more: [PersonalAIUsageEntry]) {
        for entry in more { add(entry) }
    }
}
