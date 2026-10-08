#if DEBUG
import Foundation
import OSLog

/// This process's own unified log: every `Logger` entry and each framework fault raised in it.
enum AgentLogReader {
    static func entries(_ query: AgentLogQuery) async throws -> [AgentLogQuery.Entry] {
        try await Task.detached(priority: .userInitiated) { try read(query) }.value
    }

    private static func read(_ query: AgentLogQuery) throws -> [AgentLogQuery.Entry] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let start = store.position(date: Date().addingTimeInterval(-query.since))
        var admitted: [AgentLogQuery.Entry] = []
        for case let entry as OSLogEntryLog in try store.getEntries(at: start) {
            let level = level(of: entry.level)
            guard
                query.admits(
                    level: level, subsystem: entry.subsystem, category: entry.category,
                    message: entry.composedMessage)
            else { continue }
            admitted.append(
                AgentLogQuery.Entry(
                    date: entry.date, level: level.rawValue, subsystem: entry.subsystem,
                    category: entry.category, message: entry.composedMessage))
        }
        return query.trimmed(admitted)
    }

    private static func level(of level: OSLogEntryLog.Level) -> AgentLogQuery.Level {
        switch level {
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .error: .error
        case .fault: .fault
        default: .debug
        }
    }
}
#endif
