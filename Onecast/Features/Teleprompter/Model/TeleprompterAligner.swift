import Foundation

/// Follows a speaker through the script from what a recognizer heard last.
enum TeleprompterAligner {
    /// How far ahead a match may land: a skipped sentence, not a jump to the next page.
    static let lookahead = 24
    /// How many of the latest heard words are matched as a phrase.
    static let phrase = 4

    /// The index of the next word to say. It never moves back: a recognizer revising its guess
    /// must not drag the prompter backwards under the speaker.
    static func advance(
        from position: Int, heard: [String], in script: TeleprompterScript
    ) -> Int {
        let heard = heard.map(TeleprompterScript.key).filter { !$0.isEmpty }.suffix(phrase)
        guard !heard.isEmpty else { return position }
        let words = script.words
        let start = script.nextSpoken(from: position)
        let end = min(words.count, start + lookahead)
        guard start < end else { return position }
        var best: (index: Int, score: Int)?
        for candidate in start..<end where !words[candidate].isCue {
            let score = matched(heard: Array(heard), endingAt: candidate, in: words)
            guard score > 0 else { continue }
            // Further away needs more of the phrase to agree, so one common word can't leap ahead.
            let needed = candidate - start <= 2 ? 1 : 2
            guard score >= needed else { continue }
            if best == nil || score > best!.score { best = (candidate, score) }
        }
        guard let best else { return position }
        return script.nextSpoken(from: best.index + 1)
    }

    /// How many of the heard words, read backwards from the last, line up with the script ending at `index`.
    private static func matched(
        heard: [String], endingAt index: Int, in words: [TeleprompterScript.Word]
    ) -> Int {
        var score = 0
        var scriptIndex = index
        for spoken in heard.reversed() {
            while scriptIndex >= 0, words[scriptIndex].isCue || words[scriptIndex].key.isEmpty {
                scriptIndex -= 1
            }
            guard scriptIndex >= 0, similar(spoken, words[scriptIndex].key) else { break }
            score += 1
            scriptIndex -= 1
        }
        return score
    }

    /// Equal, or one edit apart once a word is long enough for a slip to be a slip.
    static func similar(_ spoken: String, _ written: String) -> Bool {
        if spoken == written { return true }
        guard min(spoken.count, written.count) >= 4 else { return false }
        if spoken.hasPrefix(written) || written.hasPrefix(spoken) { return true }
        return distance(Array(spoken), Array(written)) <= 1
    }

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        guard abs(a.count - b.count) <= 1 else { return 2 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(
                    previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
