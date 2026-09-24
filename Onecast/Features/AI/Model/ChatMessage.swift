import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    enum State: String, Equatable, Sendable {
        case streaming
        case complete
        case failed
        /// The user stopped the reply, or a snapshot outlived the stream that fed it.
        case interrupted
    }

    let id: UUID
    let role: Role
    var text: String
    var state: State
    let sentAt: Date
    let images: [AIImage]
    /// Sent PDFs; a text file is not one, its contents reached the model as text.
    let documents: [AIDocument]
    /// Web searches the reply made, in order; each sits in the text where it happened.
    var searches: [ChatSearch]
    /// Tools the reply called, pinned the same way; the calls themselves never enter the context.
    var toolUses: [ChatToolUse]
    /// What the model shared of its thinking, a block per stretch of it, each where it happened.
    var reasoning: [ChatReasoning]
    /// What the route reported for this reply; the context gauge reads the latest one.
    var usage: AIUsage?

    init(
        id: UUID = UUID(), role: Role, text: String, state: State = .complete,
        sentAt: Date = Date(), images: [AIImage] = [], documents: [AIDocument] = [],
        searches: [ChatSearch] = [],
        toolUses: [ChatToolUse] = [], reasoning: [ChatReasoning] = [], usage: AIUsage? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.sentAt = sentAt
        self.images = images
        self.documents = documents
        self.searches = searches
        self.toolUses = toolUses
        self.reasoning = reasoning
        self.usage = usage
    }

    /// The next search, call or stretch of thinking's place: with no text between, offsets tie.
    var nextSequence: Int { searches.count + toolUses.count + reasoning.count }

    /// The reply split around what it did: thinking, search or tool, text… each where it happened.
    var segments: [ChatSegment] {
        let interruptions =
            (reasoning.map {
                (offset: $0.textOffset, sequence: $0.sequence, segment: ChatSegment.reasoning($0))
            }
            + searches.map {
                (offset: $0.textOffset, sequence: $0.sequence, segment: ChatSegment.search($0))
            }
            + toolUses.map {
                (offset: $0.textOffset, sequence: $0.sequence, segment: ChatSegment.tools([$0]))
            })
            .sorted { ($0.offset, $0.sequence) < ($1.offset, $1.sequence) }
        var segments: [ChatSegment] = []
        var rest = Substring(text)
        var consumed = 0
        for interruption in interruptions {
            let take = max(0, min(interruption.offset - consumed, rest.count))
            if take > 0 { segments.append(.text(String(rest.prefix(take)))) }
            if case .tools(let uses) = interruption.segment,
                case .tools(let previous) = segments.last
            {
                segments[segments.count - 1] = .tools(previous + uses)
            } else {
                segments.append(interruption.segment)
            }
            rest = rest.dropFirst(take)
            consumed += take
        }
        if !rest.isEmpty { segments.append(.text(String(rest))) }
        return segments
    }
}

struct ChatSearch: Equatable, Hashable, Sendable {
    var query: String?
    var isComplete: Bool
    /// Characters of reply text that had arrived when the search began.
    let textOffset: Int
    let sequence: Int
}

/// One tool call inside a reply: live while it runs, a record of what ran once it is done.
struct ChatToolUse: Equatable, Hashable, Sendable {
    enum State: String, Equatable, Hashable, Sendable {
        case running
        case completed
        case failed
    }

    let callID: String
    let origin: String
    let title: String
    var state: State
    /// Characters of reply text that had arrived when the call started.
    let textOffset: Int
    let sequence: Int

    var label: String {
        let verb = state == .running ? "Calling" : "Called"
        return origin.isEmpty ? "\(verb) \(title)" : "\(verb) \(origin) · \(title)"
    }
}

extension Array where Element == ChatToolUse {
    var runningCall: ChatToolUse? { last { $0.state == .running } }
    var isLive: Bool { runningCall != nil }
    var failedCount: Int { count { $0.state == .failed } }

    var completedLabel: String {
        let label = "Called \(count) tools"
        let failures = failedCount
        return failures == 0 ? label : "\(label) · \(failures) failed"
    }
}

/// One stretch of thinking: a reply may think, call a tool, think again, then answer.
struct ChatReasoning: Equatable, Hashable, Sendable {
    var text: String
    /// Characters of reply text that had arrived when this stretch began.
    let textOffset: Int
    let sequence: Int
    /// Until the reply moved on (text, a search, a call) or ended; nil while it is still thinking.
    var duration: TimeInterval?
}

enum ChatSegment: Equatable, Hashable {
    case text(String)
    case search(ChatSearch)
    case tools([ChatToolUse])
    case reasoning(ChatReasoning)
}
