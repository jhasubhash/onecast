import Foundation

/// What a typed query is asking for. Extensible like `Notification.Name`: a workflow can mint its own
/// intent as a `static let` in its own file and register a detector for it, without touching this one.
struct QueryIntent: Hashable, Sendable {
    let id: String
    init(_ id: String) { self.id = id }
}

extension QueryIntent {
    static let reminder = QueryIntent("reminder")
    static let shellCommand = QueryIntent("shellCommand")
    static let fileSearch = QueryIntent("fileSearch")
    static let aiQuestion = QueryIntent("aiQuestion")
    /// One intent per quicklink, keyed by its id, so a user-authored trigger can float exactly
    /// that quicklink's fallback without colliding with any built-in or another quicklink.
    static func quicklink(_ id: UUID) -> QueryIntent {
        QueryIntent("quicklink:" + id.uuidString.lowercased())
    }
}

/// One intent paired with the strength of its signal; a higher score wins.
struct ScoredIntent: Hashable, Sendable {
    let intent: QueryIntent
    let score: Double
}

/// Scores how strongly one query expresses one intent. `0` means "no signal from me"; callers compare
/// scores across detectors, so a detector's range only has to be consistent with its own kind.
protocol IntentDetector: Sendable {
    var intent: QueryIntent { get }
    func score(_ query: QueryText) -> Double
}

/// Ranks a query across a set of detectors. Pure and `Sendable`, so any workflow can hold one: the
/// launcher ranks its fallbacks with it today; a command bar or an AI router can reuse it unchanged.
struct IntentClassifier: Sendable {
    private let detectors: [any IntentDetector]
    /// A signal must clear this to count, keeping a broad catch-all from matching every phrase.
    private let threshold: Double

    init(detectors: [any IntentDetector], threshold: Double = 0.5) {
        self.detectors = detectors
        self.threshold = threshold
    }

    /// Every intent whose signal clears the threshold, strongest first; a tie keeps detector order,
    /// so a more specific detector listed earlier wins over a broader one.
    func ranked(_ text: String) -> [ScoredIntent] {
        let query = QueryText(text)
        guard !query.isEmpty else { return [] }
        var scored: [(order: Int, result: ScoredIntent)] = []
        for (index, detector) in detectors.enumerated() {
            let score = detector.score(query)
            guard score >= threshold else { continue }
            scored.append((index, ScoredIntent(intent: detector.intent, score: score)))
        }
        scored.sort { lhs, rhs in
            lhs.result.score != rhs.result.score
                ? lhs.result.score > rhs.result.score
                : lhs.order < rhs.order
        }
        return scored.map(\.result)
    }

    /// The single best intent, or nil when nothing clears the threshold.
    func best(_ text: String) -> QueryIntent? { ranked(text).first?.intent }
}

extension IntentClassifier {
    /// The built-in detectors, ordered specific-first so a tie favours the narrower one. Exposed so
    /// a caller can append its own — the launcher adds one per trigger-bearing quicklink.
    static let standardDetectors: [any IntentDetector] = [
        ReminderIntentDetector(),
        ShellCommandIntentDetector(),
        FileSearchIntentDetector(),
        AIQuestionIntentDetector(),
    ]

    /// The intents Onecast recognises without any user configuration.
    static let standard = IntentClassifier(detectors: standardDetectors)
}
