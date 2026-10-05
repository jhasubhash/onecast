import Foundation

/// Where an AI Usage widget's limits come from.
enum PersonalAIUsageLimitsSource: String, Sendable, CaseIterable {
    case codex
    case copilot

    static let standard = PersonalAIUsageLimitsSource.codex

    var title: String {
        switch self {
        case .codex: "Codex"
        case .copilot: "GitHub Copilot"
        }
    }

    /// The name a tile puts before a window: "Codex · Weekly", "Copilot · Premium".
    var shortTitle: String {
        switch self {
        case .codex: "Codex"
        case .copilot: "Copilot"
        }
    }
}

/// A GitHub Copilot account's monthly quotas, as `api.github.com/copilot_internal/user` reports them.
struct PersonalCopilotQuota: Sendable, Equatable {
    struct Bucket: Sendable, Equatable, Identifiable {
        let id: String
        let title: String
        let percentRemaining: Double
        let remaining: Int
        let entitlement: Int

        var usedPercent: Int { Int((100 - min(max(percentRemaining, 0), 100)).rounded()) }
    }

    /// "Business", "Pro", "Free"; nil when the account names none.
    let plan: String?
    let resetsAt: Date?
    /// Only metered quotas, premium requests first; an unlimited one has nothing to show.
    let buckets: [Bucket]

    private static let order = ["premium_interactions", "chat", "completions"]

    static func parse(_ data: Data) -> PersonalCopilotQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let snapshots = root["quota_snapshots"] as? [String: Any]
        else { return nil }
        let buckets = snapshots.compactMap { id, value -> Bucket? in
            guard let fields = value as? [String: Any], fields["unlimited"] as? Bool != true,
                let percent = number(fields["percent_remaining"])
            else { return nil }
            return Bucket(
                id: id, title: title(of: id), percentRemaining: percent,
                remaining: Int(number(fields["remaining"]) ?? 0),
                entitlement: Int(number(fields["entitlement"]) ?? 0))
        }
        .sorted { rank($0.id) < rank($1.id) }
        let plan = (root["copilot_plan"] as? String).flatMap { $0.isEmpty ? nil : $0.capitalized }
        return PersonalCopilotQuota(plan: plan, resetsAt: resetDate(root), buckets: buckets)
    }

    private static func title(of id: String) -> String {
        switch id {
        case "premium_interactions": "Premium requests"
        case "chat": "Chat"
        case "completions": "Completions"
        default: id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func rank(_ id: String) -> Int {
        order.firstIndex(of: id) ?? order.count
    }

    /// JSON numbers arrive as Int or Double depending on the value, so both read as Double.
    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// The exact UTC instant when present, else the plain date taken as UTC midnight.
    private static func resetDate(_ root: [String: Any]) -> Date? {
        if let stamp = root["quota_reset_date_utc"] as? String {
            let precise = ISO8601DateFormatter()
            precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = precise.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp) {
                return date
            }
        }
        guard let day = root["quota_reset_date"] as? String else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withFullDate]
        return plain.date(from: day)
    }
}
