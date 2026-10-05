import OnecastPluginKit
import SwiftUI

/// The AI Usage popover: every provider with data in full, and the way to look again.
struct AIUsagePopover: View {
    let model: AIUsageModel
    let context: DockWidgetContext
    private let stored: AIUsageStoredSettings

    private static let refreshSeconds: TimeInterval = 30
    private static let meterHeight: CGFloat = 6
    private static let markSize: CGFloat = 14

    private let locale = Locale.autoupdatingCurrent
    private let calendar = Calendar.autoupdatingCurrent

    init(model: AIUsageModel, context: DockWidgetContext) {
        self.model = model
        self.context = context
        stored = AIUsageStoredSettings(instanceID: context.instanceID)
    }

    var body: some View {
        let settings = stored.value
        TimelineView(.periodic(from: .now, by: Self.refreshSeconds)) { timeline in
            let limits = model.limits
            let activity = model.activity
            let hasActivity = activity?.summaries.isEmpty == false
            let resolution = PersonalAIUsageContent.resolve(
                preferred: settings.content, hasLimits: limits != nil, hasActivity: hasActivity)
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                if let resolution, resolution.isFallback {
                    fallbackNote(settings.content, showing: resolution.content)
                }
                ForEach([settings.content, settings.content.other], id: \.self) { kind in
                    switch kind {
                    case .limits:
                        if limits != nil || settings.content == .limits {
                            limitsSection(limits, measure: settings.measure, now: timeline.date)
                        }
                    case .activity:
                        if let activity, hasActivity {
                            activitySection(activity, display: settings.display, now: timeline.date)
                        }
                    }
                }
                if !hasActivity { emptyActivity(activity) }
                footer
            }
            .padding(PersonalPopover.padding)
        }
        .frame(width: PersonalPopover.width)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            SymbolImage(name: AIUsageGlyph.widget, size: Theme.Typography.menuSymbolSize)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("AI Usage")
                .font(Theme.Typography.panelTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func fallbackNote(_ chosen: PersonalAIUsageContent, showing shown: PersonalAIUsageContent)
        -> some View
    {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            SymbolImage(name: "info.circle", size: Self.markSize)
            Text("\(chosen.title) has no data yet, so \(shown.title) is shown instead.")
                .font(Theme.Typography.rowTrailing)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
    }

    // MARK: - Limits

    private func limitsSection(
        _ rows: [AIUsageModel.LimitRow]?, measure: PersonalAIUsageMeasure, now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            let source = stored.value.limitsSource
            sectionHeader(
                mark: source.markName, title: "\(source.title) limits",
                trailing: model.limitsPlan)
            if let rows {
                ForEach(rows) { limitRow($0, measure: measure, now: now) }
            } else {
                limitsStatus
            }
        }
    }

    private func limitRow(
        _ row: AIUsageModel.LimitRow, measure: PersonalAIUsageMeasure, now: Date
    ) -> some View {
        let window = row.window
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(window.title(fallback: row.fallbackTitle))
                    .font(Theme.Typography.rowTitle.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text(window.caption(measure))
                    .font(Theme.Typography.rowTrailing)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            AIUsageBar(progress: window.fraction(measure), tint: AIUsageCell.limitTint(window))
                .frame(height: Self.meterHeight)
            if let resetsAt = window.resetsAt {
                HStack {
                    Text(
                        "Resets "
                            + PersonalAIUsageReset.phrase(resetsAt, now: now, calendar: calendar))
                    Spacer(minLength: 0)
                    Text(resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                }
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var limitsStatus: some View {
        if stored.value.limitsSource == .codex {
            codexStatus
        } else {
            remoteStatus(stored.value.limitsSource)
        }
    }

    @ViewBuilder
    private func remoteStatus(_ source: PersonalAIUsageLimitsSource) -> some View {
        switch model.currentRemoteStatus {
        case .checking:
            statusText("Checking \(source.title)…")
        case .ready:
            statusText("\(source.title) reports no metered limit for this account.")
        case .failed(let problem):
            statusText(problem.message)
            if problem.canRetry { retryButton }
        }
    }

    private var retryButton: some View {
        BarButton(chrome: .rounded, action: { model.requestRefresh() }) {
            Text("Try again")
                .font(Theme.Typography.bar)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.leading, -Theme.Spacing.md)
    }

    @ViewBuilder
    private var codexStatus: some View {
        switch model.codexStatus {
        case .connected:
            statusText("Codex did not report any rate limits for this account.")
        case .checking:
            statusText("Checking Codex…")
        case .turnedOff:
            statusText("Codex is turned off in Onecast's AI settings.")
        case .notInstalled:
            statusText("Codex is not installed on this Mac.")
        case .signedOut:
            Text("Codex is installed but signed out. Sign in with `codex login`, then refresh.")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            statusText(message, tint: Theme.Colors.destructive)
            retryButton
        }
    }

    // MARK: - Activity

    private func activitySection(
        _ activity: AIUsageModel.Activity, display: PersonalAIUsageDisplay, now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Activity")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                Text(activity.range.title)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    ForEach(activity.summaries) { summary in
                        providerTable(summary, range: activity.range, now: now)
                    }
                }
            }
            .frame(maxHeight: PersonalPopover.listMaxHeight)
            .overflowFade()
            .thinScrollbar()
            Text(Self.displayNote(display))
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func providerTable(
        _ summary: PersonalAIUsageSummary, range: PersonalAIUsageRange, now: Date
    ) -> some View {
        let total = summary.series.total
        let shown = summary.series.days.reversed().filter {
            !$0.tokens.isZero || calendar.isDate($0.start, inSameDayAs: now)
        }
        let quiet = summary.series.days.count - shown.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(
                mark: summary.provider.markName, title: summary.provider.title,
                trailing: PersonalAIUsageFormat.tokens(total.total) + " tokens")
            Grid(
                alignment: .trailing, horizontalSpacing: Theme.Spacing.md,
                verticalSpacing: Theme.Spacing.xs
            ) {
                GridRow {
                    Text("Day").frame(maxWidth: .infinity, alignment: .leading)
                    Text("In")
                    Text("Out")
                    Text("Total")
                }
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
                GridRow {
                    Text(range.title).frame(maxWidth: .infinity, alignment: .leading)
                    figure(total.input)
                    figure(total.output)
                    figure(total.total)
                }
                .font(Theme.Typography.rowTrailing.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                ForEach(shown) { day in
                    GridRow {
                        Text(dayTitle(day.start, now: now))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tooltip(exactTokens(day.tokens))
                        figure(day.tokens.input)
                        figure(day.tokens.output)
                        figure(day.tokens.total)
                    }
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(
                        day.tokens.isZero ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                }
            }
            if quiet > 0 {
                Text(quiet == 1 ? "No activity on 1 other day" : "No activity on \(quiet) other days")
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            if total.cache > 0 {
                let cache = PersonalAIUsageFormat.tokens(total.cache)
                Text("Cache: \(cache) tokens, listed apart and not counted")
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func figure(_ count: Int) -> some View {
        Text(count == 0 ? "—" : PersonalAIUsageFormat.tokens(count)).monospacedDigit()
    }

    private func dayTitle(_ day: Date, now: Date) -> String {
        calendar.isDate(day, inSameDayAs: now)
            ? "Today"
            : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func exactTokens(_ tokens: PersonalAIUsageTokens) -> String {
        let input = PersonalAIUsageFormat.exact(tokens.input, locale: locale)
        let output = PersonalAIUsageFormat.exact(tokens.output, locale: locale)
        return "\(input) in · \(output) out"
    }

    private static func displayNote(_ display: PersonalAIUsageDisplay) -> String {
        let counting = "Input and output tokens are counted; cache tokens are not."
        switch display {
        case .numbers: return "Numbers add up the range. " + counting
        case .rings:
            return "A ring is today's tokens as a share of your busiest day in this range. " + counting
        case .bars: return "Bars are one per day, each a share of the busiest day. " + counting
        }
    }

    @ViewBuilder
    private func emptyActivity(_ activity: AIUsageModel.Activity?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(activity == nil ? "Reading local logs…" : "No Claude Code or Codex activity found")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let activity {
                ForEach(PersonalAIUsageProvider.allCases) { provider in
                    let found = activity.foundFolders.contains(provider)
                    let range = activity.range.title.lowercased()
                    statusText(
                        found
                            ? "\(provider.title): nothing in the logs for \(range)."
                            : "\(provider.title): no logs found in \(provider.logFolder).")
                }
            }
        }
    }

    // MARK: - Parts

    private var footer: some View {
        HStack {
            Group {
                if let updated = model.updatedAt {
                    Text("Updated \(updated.formatted(.relative(presentation: .named, unitsStyle: .wide)))")
                } else {
                    Text("Not updated yet")
                }
            }
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textTertiary)
            Spacer(minLength: 0)
            BarButton(chrome: .rounded, action: { model.requestRefresh() }) {
                HStack(spacing: Theme.Spacing.sm) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        SymbolImage(name: "arrow.clockwise", size: Self.markSize)
                    }
                    Text("Refresh").font(Theme.Typography.bar)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .tooltip("Rescan the logs and check Codex again")
            .accessibilityLabel("Refresh AI usage")
        }
    }

    private func sectionHeader(mark: String, title: String, trailing: String?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            SymbolImage(name: mark, size: Self.markSize)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(title)
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func statusText(_ message: String, tint: Color = Theme.Colors.textSecondary)
        -> some View
    {
        Text(verbatim: message)
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
