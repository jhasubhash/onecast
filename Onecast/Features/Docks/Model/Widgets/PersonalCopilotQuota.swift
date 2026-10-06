import Foundation

/// The service an AI Usage widget follows: its limits, and its token activity where it keeps logs.
enum PersonalAIUsageLimitsSource: String, Sendable, CaseIterable {
    case codex
    case claude
    case copilot

    static let standard = PersonalAIUsageLimitsSource.codex

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .copilot: "GitHub Copilot"
        }
    }

    /// The name a tile puts before a window: "Codex · Weekly", "Copilot · Premium".
    var shortTitle: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .copilot: "Copilot"
        }
    }

    /// Whose local logs the widget adds up; Copilot keeps none.
    var activityProvider: PersonalAIUsageProvider? {
        switch self {
        case .codex: .codex
        case .claude: .claudeCode
        case .copilot: nil
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
        let used: Int
        let unit: PersonalAIUsageLimitsReport.Amounts.Unit
        let overage: Int
        let overagePermitted: Bool

        var usedPercent: Int { Int((100 - min(max(percentRemaining, 0), 100)).rounded()) }

        /// Nil without an allowance to count against.
        var amounts: PersonalAIUsageLimitsReport.Amounts? {
            guard entitlement > 0 else { return nil }
            return .init(
                used: used, remaining: remaining, entitlement: entitlement, unit: unit,
                overage: overage, overagePermitted: overagePermitted)
        }
    }

    var report: PersonalAIUsageLimitsReport {
        PersonalAIUsageLimitsReport(
            plan: plan,
            windows: buckets.map {
                PersonalAIUsageLimitsReport.Window(
                    id: $0.id, fallbackTitle: $0.title, usedPercent: $0.usedPercent,
                    durationMinutes: nil, resetsAt: resetsAt, amounts: $0.amounts)
            },
            unlimited: unlimited)
    }

    /// "Business", "Pro", "Free"; nil when the account names none.
    let plan: String?
    let resetsAt: Date?
    /// Only metered quotas, premium requests first; an unlimited one has nothing to show.
    let buckets: [Bucket]
    /// Titles of the quotas the plan leaves unmetered, in the same order.
    let unlimited: [String]

    private static let order = ["premium_interactions", "chat", "completions"]

    static func parse(_ data: Data) -> PersonalCopilotQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let snapshots = root["quota_snapshots"] as? [String: Any]
        else { return nil }
        let quotas = snapshots.compactMap { id, value in
            (value as? [String: Any]).map { (id: id, fields: $0) }
        }
        .sorted { rank($0.id) < rank($1.id) }
        let buckets = quotas.compactMap { id, fields -> Bucket? in
            guard fields["unlimited"] as? Bool != true, let percent = number(fields["percent_remaining"])
            else { return nil }
            let remaining = Int(number(fields["remaining"]) ?? 0)
            let entitlement = Int(number(fields["entitlement"]) ?? 0)
            let tokenBased =
                (fields["token_based_billing"] as? Bool ?? root["token_based_billing"] as? Bool) == true
            return Bucket(
                id: id, title: title(of: id), percentRemaining: percent,
                remaining: remaining, entitlement: entitlement,
                used: Int(number(fields["credits_used"]) ?? Double(max(0, entitlement - remaining))),
                unit: tokenBased ? .credits : .requests,
                overage: Int(number(fields["overage_count"]) ?? 0),
                overagePermitted: fields["overage_permitted"] as? Bool == true)
        }
        let creditBilled = root["token_based_billing"] as? Bool == true
        // Credit billing charges chat by the token, though GitHub still flags its old quota unlimited.
        let unlimited = quotas.filter {
            $0.fields["unlimited"] as? Bool == true && !(creditBilled && $0.id == "chat")
        }
        .map { title(of: $0.id) }
        let plan = (root["copilot_plan"] as? String).flatMap { $0.isEmpty ? nil : $0.capitalized }
        return PersonalCopilotQuota(
            plan: plan, resetsAt: resetDate(root), buckets: buckets, unlimited: unlimited)
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
        if let stamp = root["quota_reset_date_utc"] as? String,
            let date = PersonalAIUsageISODate.parse(stamp)
        {
            return date
        }
        guard let day = root["quota_reset_date"] as? String else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withFullDate]
        return plain.date(from: day)
    }
}
