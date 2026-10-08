import Foundation

/// Which of the process's own unified-log entries `logs` returns, newest last.
struct AgentLogQuery: Equatable, Sendable {
    enum Level: String, CaseIterable, Comparable, Sendable {
        case debug, info, notice, error, fault

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }

        private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    struct Entry: Codable, Equatable, Sendable {
        let date: Date
        let level: String
        let subsystem: String
        let category: String
        let message: String
    }

    static let maximumLimit = 2000

    var since: Double = 60
    var minimumLevel: Level = .debug
    var category: String?
    var contains: String?
    /// Off: Onecast's own subsystems only. On: AppKit, SwiftUI and every framework in-process.
    var allSubsystems = false
    var limit = 200

    init() {}

    init(_ arguments: AgentCommand.Arguments) throws {
        since = try arguments.optional("since") ?? since
        if let name: String = try arguments.optional("level") {
            guard let level = Level(rawValue: name) else {
                throw AgentCommand.DecodeError.invalid(
                    "\"level\" is one of " + Level.allCases.map(\.rawValue).joined(separator: ", ") + ".")
            }
            minimumLevel = level
        }
        category = try arguments.optional("category")
        contains = try arguments.optional("contains")
        allSubsystems = try arguments.optional("allSubsystems") ?? false
        limit = min(max(1, try arguments.optional("limit") ?? limit), Self.maximumLimit)
        guard since > 0 else { throw AgentCommand.DecodeError.invalid("\"since\" must be above 0.") }
    }

    /// Onecast's loggers name the bundle id, or the older `com.onecast` and `com.onecast.perf`.
    static let ownSubsystemPrefix = "com.onecast"

    static func isOwnSubsystem(_ subsystem: String) -> Bool {
        subsystem.hasPrefix(ownSubsystemPrefix)
    }

    func admits(level: Level, subsystem: String, category: String, message: String) -> Bool {
        level >= minimumLevel
            && (allSubsystems || Self.isOwnSubsystem(subsystem))
            && (self.category.map { $0.caseInsensitiveCompare(category) == .orderedSame } ?? true)
            && (contains.map { message.localizedCaseInsensitiveContains($0) } ?? true)
    }

    /// The newest `limit` of what was admitted, still oldest first.
    func trimmed(_ entries: [Entry]) -> [Entry] {
        Array(entries.suffix(limit))
    }
}
