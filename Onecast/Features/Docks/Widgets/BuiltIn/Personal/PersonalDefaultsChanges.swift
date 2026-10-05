import Foundation

enum PersonalDefaults {
    /// A wake-up on every UserDefaults change, so a widget re-reads its settings without polling.
    static func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in NotificationCenter.default.notifications(
                    named: UserDefaults.didChangeNotification)
                {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
