import Foundation

/// A service's limits, normalised so Copilot and Claude draw the way Codex does.
struct PersonalAIUsageLimitsReport: Sendable, Equatable {
    struct Window: Sendable, Equatable, Identifiable {
        let id: String
        let fallbackTitle: String
        let usedPercent: Int
        let durationMinutes: Int?
        let resetsAt: Date?
        /// The counts behind the percentage, where the service gives them.
        var amounts: Amounts? = nil
    }

    struct Amounts: Sendable, Equatable {
        enum Unit: String, Sendable {
            case credits
            case requests
        }

        let used: Int
        let remaining: Int
        let entitlement: Int
        let unit: Unit
        /// Usage past the allowance, billed separately where the plan permits it.
        let overage: Int
        let overagePermitted: Bool
    }

    /// "Business", "Max", "Enterprise"; nil when the account names none.
    let plan: String?
    let windows: [Window]
    /// Titles of quotas the plan does not meter: "Chat", "Completions".
    var unlimited: [String] = []
}

/// Why a service's limits could not be read, worded for the popover.
struct PersonalAIUsageLimitsProblem: Error, Sendable, Equatable {
    let message: String
    /// Whether Try again can help, rather than something the user must change first.
    let canRetry: Bool
}

enum PersonalAIUsageISODate {
    /// With or without fractional seconds, and with an offset or a `Z`.
    static func parse(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
