import SwiftUI

extension PersonalAIUsageProvider {
    /// The brand mark the AI model pickers already bundle; the popover draws it, tiles use a dot.
    var markName: String {
        switch self {
        case .claudeCode: AIBrand.claude.assetName
        case .codex: AIBrand.openAI.assetName
        }
    }

    var shortTitle: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        }
    }

    /// The dot that tells one provider's cell from another's.
    var accent: Color {
        switch self {
        case .claudeCode: .orange
        case .codex: .teal
        }
    }
}

extension PersonalAIUsageLimitsSource {
    /// The brand mark beside the popover's limits heading.
    var markName: String {
        switch self {
        case .codex: AIBrand.openAI.assetName
        case .claude: AIBrand.claude.assetName
        case .copilot: "BrandGitHub"
        }
    }
}

enum AIUsageGlyph {
    static let widget = "gauge.with.dots.needle.33percent"
}

/// One thing a tile shows, resolved from limits or activity so the layouts need not know which.
struct AIUsageCell: Identifiable, Equatable {
    let id: String
    /// Names for the header or the label under a value, longest first; the first that fits shows.
    let labels: [String]
    let figure: String
    /// The unit or span under the figure: "left", "today", "7 days".
    let caption: String
    /// What the figure is, under any chart: when a limit resets, or the in-out split.
    let bottoms: [String]
    let progress: Double?
    /// One fraction per day, oldest first; each a share of the busiest day.
    let days: [Double]?
    let tint: Color
    let spoken: String

    func label(_ index: Int) -> String { labels[min(index, labels.count - 1)] }

    func bottom(_ index: Int) -> String { bottoms[min(index, bottoms.count - 1)] }
}

struct AIUsagePlan {
    let resolution: PersonalAIUsageResolution?
    let cells: [AIUsageCell]
    /// The one cell a compact tile shows.
    let summary: AIUsageCell?
    /// Nothing is known yet because the first scan has not finished.
    let isChecking: Bool

    static func empty(isChecking: Bool) -> AIUsagePlan {
        AIUsagePlan(resolution: nil, cells: [], summary: nil, isChecking: isChecking)
    }

    var spoken: String {
        guard resolution != nil else { return "AI Usage, no data" }
        return "AI Usage. " + cells.map(\.spoken).joined(separator: ". ")
    }
}

extension AIUsageModel {
    func plan(settings: PersonalAIUsageSettings, now: Date, calendar: Calendar) -> AIUsagePlan {
        let limits = limits
        let activity = activity
        let hasActivity = activity?.summaries.isEmpty == false
        guard
            let resolution = PersonalAIUsageContent.resolve(
                preferred: settings.content, hasLimits: limits != nil, hasActivity: hasActivity)
        else { return .empty(isChecking: limits == nil && (activity == nil || isRefreshing)) }

        switch resolution.content {
        case .limits:
            let cells = (limits ?? []).map {
                AIUsageCell.limit($0, measure: settings.measure, now: now, calendar: calendar)
            }
            return AIUsagePlan(
                resolution: resolution, cells: cells, summary: cells.first, isChecking: false)
        case .activity:
            guard let activity else { return .empty(isChecking: true) }
            let cells = activity.summaries.map {
                AIUsageCell.activity(
                    labels: [$0.provider.title, $0.provider.shortTitle],
                    spokenTitle: $0.provider.title, tint: $0.provider.accent,
                    series: $0.series, range: activity.range, display: settings.display)
            }
            return AIUsagePlan(
                resolution: resolution, cells: cells, summary: cells.first, isChecking: false)
        }
    }
}

extension AIUsageCell {
    /// A window leaves this much and it reads as running low, then as nearly spent.
    private static let lowRemaining = 25
    private static let criticalRemaining = 10

    /// By what is left, so Remaining and Used colour a window alike.
    static func limitTint(_ window: PersonalAIUsageLimitWindow) -> Color {
        if window.remaining <= criticalRemaining { return Theme.Colors.destructive }
        return window.remaining <= lowRemaining ? Theme.Colors.warning : Theme.Colors.success
    }

    static func limit(
        _ row: AIUsageModel.LimitRow, measure: PersonalAIUsageMeasure, now: Date, calendar: Calendar
    ) -> AIUsageCell {
        let window = row.window
        let source = row.source.shortTitle
        let title = window.title(fallback: row.fallbackTitle)
        let short = window.shortTitle(fallback: row.fallbackTitle)
        let phrase = window.resetsAt.map {
            PersonalAIUsageReset.phrase($0, now: now, calendar: calendar)
        }
        let reset = phrase.map { ["resets \($0)", $0, $0.replacingOccurrences(of: "in ", with: "")] }
        return AIUsageCell(
            id: "\(row.source.rawValue).\(row.id)",
            labels: ["\(source) · \(title)", "\(source) \(short)", title, short],
            figure: "\(window.percent(measure))%", caption: measure.suffix, bottoms: reset ?? [],
            progress: window.fraction(measure), days: nil, tint: limitTint(window),
            spoken: "\(source) \(title) limit, \(window.caption(measure))"
                + (reset.map { ", \($0[0])" } ?? ""))
    }

    /// Numbers and Bars total the range; Rings put today against the busiest day.
    static func activity(
        labels: [String], spokenTitle: String, tint: Color, series: PersonalAIUsageSeries,
        range: PersonalAIUsageRange, display: PersonalAIUsageDisplay
    ) -> AIUsageCell {
        let total = series.total
        let rangeFigure = PersonalAIUsageFormat.tokens(total.total)
        let input = PersonalAIUsageFormat.tokens(total.input)
        let output = PersonalAIUsageFormat.tokens(total.output)
        let split = ["\(input) in · \(output) out", "\(input) · \(output)", "\(output) out"]
        let locale = Locale.autoupdatingCurrent
        let spoken =
            "\(spokenTitle), \(PersonalAIUsageFormat.exact(total.total, locale: locale)) tokens, "
            + "\(PersonalAIUsageFormat.exact(total.input, locale: locale)) in and "
            + "\(PersonalAIUsageFormat.exact(total.output, locale: locale)) out, "
            + range.title.lowercased()

        switch display {
        case .numbers:
            return AIUsageCell(
                id: spokenTitle, labels: labels, figure: rangeFigure, caption: range.shortTitle,
                bottoms: split, progress: nil, days: nil, tint: tint, spoken: spoken)
        case .rings:
            return AIUsageCell(
                id: spokenTitle, labels: labels,
                figure: PersonalAIUsageFormat.tokens(series.today.total), caption: "today",
                bottoms: range == .today ? split : ["\(rangeFigure) · \(range.shortTitle)", rangeFigure],
                progress: series.todayShare, days: nil, tint: tint, spoken: spoken)
        case .bars:
            let busiest = series.busiestDayTotal
            let days = series.days.map {
                busiest > 0 ? Double($0.tokens.total) / Double(busiest) : 0
            }
            return AIUsageCell(
                id: spokenTitle, labels: labels, figure: rangeFigure, caption: range.shortTitle,
                bottoms: split, progress: nil, days: days, tint: tint, spoken: spoken)
        }
    }
}
