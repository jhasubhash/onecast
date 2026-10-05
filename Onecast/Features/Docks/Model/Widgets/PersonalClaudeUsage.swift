import Foundation

/// Claude Code's sign-in as it stores it in the keychain item `Claude Code-credentials`.
struct PersonalClaudeCredentials: Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date?
    /// "pro", "max", "enterprise".
    let subscription: String?

    static func parse(_ data: Data) -> PersonalClaudeCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let expiry = (oauth["expiresAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000)
        }
        return PersonalClaudeCredentials(
            accessToken: token, expiresAt: expiry, subscription: oauth["subscriptionType"] as? String)
    }

    /// Expired, or about to be: a minute's slack so a request never lands just after the edge.
    func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < 60
    }
}

/// Claude's plan limits as `api.anthropic.com/api/oauth/usage` reports them.
enum PersonalClaudeUsage {
    private static let windows: [(key: String, title: String, minutes: Int?)] = [
        ("five_hour", "5-hour", 300),
        ("seven_day", "Weekly", 10_080),
        ("seven_day_opus", "Weekly · Opus", nil),
        ("seven_day_sonnet", "Weekly · Sonnet", nil),
    ]

    /// The session and weekly windows always; a per-model week only when the server sends one.
    static func report(_ data: Data, plan: String?) -> PersonalAIUsageLimitsReport? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let found = windows.compactMap { window -> PersonalAIUsageLimitsReport.Window? in
            guard let fields = root[window.key] as? [String: Any] else { return nil }
            let used = (fields["utilization"] as? NSNumber)?.doubleValue ?? 0
            return PersonalAIUsageLimitsReport.Window(
                id: window.key, fallbackTitle: window.title,
                usedPercent: Int(min(max(used, 0), 100).rounded()),
                durationMinutes: window.minutes,
                resetsAt: (fields["resets_at"] as? String).flatMap(PersonalAIUsageISODate.parse))
        }
        guard !found.isEmpty else { return nil }
        return PersonalAIUsageLimitsReport(plan: plan.map(\.capitalized), windows: found)
    }
}
