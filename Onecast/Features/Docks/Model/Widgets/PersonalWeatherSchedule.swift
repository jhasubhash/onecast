import Foundation

/// When a live weather tile next asks the service.
enum PersonalWeatherSchedule {
    static let refreshInterval: TimeInterval = 30 * 60
    /// Shorter after a failure, so a Mac that woke before its Wi-Fi did recovers soon.
    static let retryInterval: TimeInterval = 5 * 60

    /// `retrying` is true after a failure that another attempt may cure.
    static func nextAttempt(after lastAttempt: Date, retrying: Bool) -> Date {
        lastAttempt.addingTimeInterval(retrying ? retryInterval : refreshInterval)
    }
}
