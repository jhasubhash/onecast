import Foundation

/// Where a form's Insert menu lands a token: over the selection, at the caret, else at the end.
enum TextInsertion {
    struct Result: Equatable {
        let text: String
        /// Just past the token, so the caret follows what was inserted.
        let caret: String.Index
    }

    /// A `selection` outside `text` is unusable, as is none: the token is then appended. A
    /// `singleLine` field flattens line breaks in the token the way it flattens a paste.
    static func inserting(
        _ token: String, into text: String, replacing selection: Range<String.Index>?,
        singleLine: Bool = false
    ) -> Result {
        let insertion = singleLine ? collapsingLineBreaks(token) : token
        let range = usable(selection, in: text) ?? text.endIndex..<text.endIndex
        var result = text
        result.replaceSubrange(range, with: insertion)
        let before = text.utf16.distance(from: text.startIndex, to: range.lowerBound)
        let caret = result.utf16.index(result.startIndex, offsetBy: before + insertion.utf16.count)
        return Result(text: result, caret: caret)
    }

    /// Each run of line breaks becomes one space, and none is left at either end.
    static func collapsingLineBreaks(_ text: String) -> String {
        text.trimmingCharacters(in: .newlines)
            .replacingOccurrences(of: #"\R+"#, with: " ", options: .regularExpression)
    }

    private static func usable(
        _ selection: Range<String.Index>?, in text: String
    ) -> Range<String.Index>? {
        guard let selection, selection.lowerBound >= text.startIndex,
            selection.upperBound <= text.endIndex
        else { return nil }
        return selection
    }
}
