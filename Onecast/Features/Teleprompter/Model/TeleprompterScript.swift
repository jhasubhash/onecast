import Foundation

/// A script split into the words the prompter shows and the speaker is matched against.
struct TeleprompterScript: Equatable, Sendable {
    struct Word: Equatable, Sendable {
        /// As written, punctuation and all.
        let text: String
        /// Lowercased letters and digits only: what a recognizer's word is compared with.
        let key: String
        /// Starts a new paragraph.
        let breaksBefore: Bool
        /// Inside `[square brackets]`: a cue for the speaker, shown but never spoken.
        let isCue: Bool
    }

    let words: [Word]

    init(_ text: String) {
        var words: [Word] = []
        var inCue = false
        for (index, paragraph) in text.components(separatedBy: .newlines).enumerated() {
            var first = true
            for token in paragraph.split(whereSeparator: \.isWhitespace).map(String.init) {
                let opens = token.hasPrefix("[")
                let cue = inCue || opens
                if opens { inCue = true }
                if inCue, token.contains("]") { inCue = false }
                words.append(
                    Word(
                        text: token, key: Self.key(token), breaksBefore: first && index > 0 && !words.isEmpty,
                        isCue: cue))
                first = false
            }
        }
        self.words = words
    }

    var isEmpty: Bool { words.isEmpty }

    static func key(_ word: String) -> String {
        String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The first spoken word at or after `index`, stepping over cues and punctuation-only tokens.
    func nextSpoken(from index: Int) -> Int {
        var index = max(index, 0)
        while index < words.count, words[index].isCue || words[index].key.isEmpty { index += 1 }
        return index
    }
}
