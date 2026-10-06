import Foundation

/// Live dictation's words since the last audio cut; a word is typed once two passes agree on it.
struct DictationLiveTranscript: Sendable {
    struct Step: Equatable, Sendable {
        var typed: [String]
        /// Heard but still changing: shown, never typed.
        var pending: [String]
        /// The pass repeated the last one, so nothing new was said and the audio can be cut here.
        var isSettled: Bool
    }

    /// Words of the current audio already typed.
    private(set) var committed = 0
    private var previous: [String]?

    mutating func update(_ hypothesis: String) -> Step {
        let words = Self.words(in: hypothesis)
        defer { previous = words }
        guard let previous else {
            return Step(typed: [], pending: Array(words.dropFirst(committed)), isSettled: false)
        }
        var agreed = 0
        while agreed < min(previous.count, words.count), previous[agreed] == words[agreed] { agreed += 1 }
        let typed = agreed > committed ? Array(words[committed..<agreed]) : []
        committed = max(committed, agreed)
        return Step(typed: typed, pending: Array(words.dropFirst(committed)), isSettled: words == previous)
    }

    /// Ends the audio before a cut; words typed past a mid-speech cut carry over, never retyped.
    mutating func close(_ hypothesis: String, carriesOver: Bool) -> [String] {
        let words = Self.words(in: hypothesis)
        let remaining = Array(words.dropFirst(committed))
        committed = carriesOver ? max(0, committed - words.count) : 0
        previous = nil
        return remaining
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

extension DictationTextFormatter.Context {
    /// The context once `typed` sits at the caret; a nil `base` means the field was unreadable.
    static func continuing(_ base: Self?, after typed: String) -> Self? {
        guard !typed.isEmpty else { return base }
        guard let base else { return Self(before: typed[...], after: ""[...]) }
        return Self(continuing: base, after: typed)
    }

    private init(continuing base: Self, after typed: String) {
        let last = typed.last { !$0.isWhitespace }
        trailing = typed.last
        lastNonWhitespace = last ?? base.lastNonWhitespace
        newParagraph = typed.reversed().prefix(while: \.isWhitespace).contains(where: \.isNewline)
            || (last == nil && base.newParagraph)
        following = base.following
    }
}
