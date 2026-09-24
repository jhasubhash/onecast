import Foundation

/// What the next message carries, measured without building it, for the window's context gauge.
struct ChatContextReport: Equatable, Sendable {
    let modelTitle: String
    let historyBytes: Int
    let budget: Int
    let sentMessages: Int
    let totalMessages: Int
    let stagedFiles: Int
    /// What the last reply reported spending, when its route reports it at all.
    let totalTokens: Int?
    let toolServers: Int

    /// Past 1 the oldest turns stop going out; an estimate, since not every route counts tokens.
    var fill: Double {
        budget > 0 ? Double(historyBytes) / Double(budget) : 0
    }
}
