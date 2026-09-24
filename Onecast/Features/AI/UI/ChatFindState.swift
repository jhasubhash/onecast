import AppKit
import Observation

/// Where a match sits: which message, which part of it, and which match within that part.
struct ChatFindOccurrence: Equatable, Hashable, Sendable {
    let messageID: UUID
    /// A reply's text segment index, or `userPart` for what the reader typed.
    let part: Int
    let index: Int

    static let userPart = -1
}

/// What the transcript highlights: the needle, and the one match Find has stepped to.
struct ChatFindHighlight: Equatable {
    let needle: String
    let current: ChatFindOccurrence?

    /// The current match's index within one part, when it is that part's to show.
    func current(in messageID: UUID, part: Int) -> Int? {
        guard let current, current.messageID == messageID, current.part == part else { return nil }
        return current.index
    }
}

/// Find in Chat for one window: a query, the matches it has, and which one is current.
@MainActor
@Observable
final class ChatFindState {
    var query = "" {
        didSet { if query != oldValue { current = 0 } }
    }
    private(set) var current = 0

    /// Re-searched only when a message or the needle changes, so a streaming flush costs one message.
    @ObservationIgnored private var cache: [UUID: (needle: String, message: ChatMessage, found: [ChatFindOccurrence])] = [:]

    var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !needle.isEmpty }

    func occurrences(in messages: [ChatMessage]) -> [ChatFindOccurrence] {
        let needle = needle
        guard !needle.isEmpty else { return [] }
        var all: [ChatFindOccurrence] = []
        for message in messages {
            if let cached = cache[message.id], cached.needle == needle, cached.message == message {
                all += cached.found
                continue
            }
            let found = Self.occurrences(of: needle, in: message)
            cache[message.id] = (needle, message, found)
            all += found
        }
        return all
    }

    func highlight(in messages: [ChatMessage]) -> ChatFindHighlight? {
        guard isSearching else { return nil }
        let found = occurrences(in: messages)
        return ChatFindHighlight(needle: needle, current: found.isEmpty ? nil : found[current % found.count])
    }

    /// Wraps both ways, as every Mac Find does.
    func step(_ delta: Int, in messages: [ChatMessage]) {
        let count = occurrences(in: messages).count
        guard count > 0 else { return }
        current = ((current + delta) % count + count) % count
    }

    /// Each part searched as the transcript renders it, so a count is a count of visible matches.
    private static func occurrences(of needle: String, in message: ChatMessage) -> [ChatFindOccurrence] {
        guard message.role == .assistant else {
            return ranges(of: needle, in: message.text).indices.map {
                ChatFindOccurrence(messageID: message.id, part: ChatFindOccurrence.userPart, index: $0)
            }
        }
        var found: [ChatFindOccurrence] = []
        for (part, segment) in message.segments.enumerated() {
            guard case .text(let text) = segment else { continue }
            let rendered = MarkdownRenderer.render(
                MarkdownBlock.parse(ChatChoices.split(text).text), style: countingStyle
            ).string
            found += ranges(of: needle, in: rendered).indices.map {
                ChatFindOccurrence(messageID: message.id, part: part, index: $0)
            }
        }
        return found
    }

    /// The one match rule; the reply view highlights with it, so the two never disagree.
    nonisolated static func ranges(of needle: String, in text: String) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        let source = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let found = source.range(
                of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            ranges.append(found)
            let next = NSMaxRange(found)
            searchRange = NSRange(location: next, length: source.length - next)
        }
        return ranges
    }

    /// Only the characters matter for counting; fonts and colours never change what renders.
    private static let countingStyle: MarkdownTextStyle = {
        let font = NSFont.systemFont(ofSize: 13)
        return MarkdownTextStyle(
            body: font, headings: [font, font, font], code: font, inlineCode: font,
            tableHeader: font, codeLabel: font, text: .labelColor, secondary: .labelColor,
            tertiary: .labelColor, checked: .labelColor, inlineCodeFill: .clear, cardFill: .clear,
            cardStroke: .clear, quoteBar: .clear, blockGap: 0, headingGap: 0, itemGap: 0,
            markerWidth: 20, markerGap: 6, cardInset: .zero, cardRadius: 0, codeHeader: 0,
            quoteBarWidth: 0, quoteGap: 0, tableColumnGap: 0, tableRowGap: 0, hairline: 1)
    }()
}
