import OnecastPluginKit
import SwiftUI

/// The Hydration tile: today's progress toward the goal and the time to the next reminder.
struct HydrationTileView: View {
    let model: HydrationModel
    let context: DockWidgetContext

    /// Fine enough that a minute-resolution countdown never reads stale, coarse enough to be free.
    private static let refreshSeconds: TimeInterval = 20
    private static let ringStroke: CGFloat = 0.07
    private static let title = "Water"
    private static let dropGlyph = "drop.fill"
    private static let bellGlyph = "bell.fill"

    private let locale = Locale.autoupdatingCurrent
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        let metrics = PersonalTileMetrics(context)
        TimelineView(.periodic(from: .now, by: Self.refreshSeconds)) { timeline in
            let progress = model.progress(now: timeline.date)
            PersonalTileCard(metrics) {
                if metrics.isCompact {
                    compact(metrics, progress, now: timeline.date)
                } else {
                    strip(metrics, progress, now: timeline.date)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(progress, now: timeline.date))
        }
        .task(id: context.instanceID) { await model.run(context) }
    }

    private func compact(
        _ metrics: PersonalTileMetrics, _ progress: HydrationProgress, now: Date
    ) -> some View {
        VStack(spacing: metrics.spacing / 2) {
            PersonalTileHeader(metrics: metrics, title: Self.title, tint: tint(progress))
            line("\(progress.percent)%", metrics.font(.display, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            reminderLine(metrics, now: now)
        }
    }

    private func strip(
        _ metrics: PersonalTileMetrics, _ progress: HydrationProgress, now: Date
    ) -> some View {
        let layout =
            metrics.isVertical
            ? AnyLayout(VStackLayout(spacing: metrics.spacing))
            : AnyLayout(HStackLayout(spacing: metrics.spacing * 2))
        return GeometryReader { proxy in
            let side =
                metrics.isVertical
                ? min(proxy.size.width, proxy.size.height * 0.4)
                : min(proxy.size.height, proxy.size.width * 0.4)
            layout {
                ring(metrics, progress)
                    .frame(width: side, height: side)
                details(metrics, progress, now: now)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func details(
        _ metrics: PersonalTileMetrics, _ progress: HydrationProgress, now: Date
    ) -> some View {
        VStack(spacing: metrics.spacing / 2) {
            PersonalTileHeader(metrics: metrics, title: Self.title, tint: tint(progress))
            line(HydrationFormat.consumed(progress, locale: locale), metrics.font(.value, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            line(HydrationFormat.goalLine(progress, locale: locale), metrics.font(.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
            reminderLine(metrics, now: now)
            if metrics.size == .expanded, let last = model.log.lastDrink {
                line(
                    "Last drink \(HydrationFormat.time(last, calendar: calendar, locale: locale))",
                    metrics.font(.caption, weight: .medium)
                )
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func reminderLine(_ metrics: PersonalTileMetrics, now: Date) -> some View {
        if let due = model.dueAt {
            let countdown = HydrationFormat.countdown(
                seconds: HydrationReminder.secondsUntil(due, now: now))
            HStack(spacing: metrics.spacing / 2) {
                SymbolImage(name: Self.bellGlyph, size: metrics.symbolSize(0.12))
                Text(countdown).minimumScaleFactor(0.6).lineLimit(1)
            }
            .font(metrics.font(.caption, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
        } else if !metrics.isCompact {
            line("Reminders off", metrics.font(.caption, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func ring(_ metrics: PersonalTileMetrics, _ progress: HydrationProgress) -> some View {
        ZStack {
            PersonalProgressRing(
                progress: progress.ringFraction, lineWidth: metrics.tileLength * Self.ringStroke,
                tint: tint(progress))
            SymbolImage(name: Self.dropGlyph, size: metrics.symbolSize(0.26))
                .foregroundStyle(tint(progress))
        }
    }

    private func line(_ text: String, _ font: Font) -> some View {
        Text(text).font(font).minimumScaleFactor(0.5).lineLimit(1)
    }

    private func tint(_ progress: HydrationProgress) -> Color {
        progress.isReached ? Theme.Colors.success : .cyan
    }

    private func accessibilitySummary(_ progress: HydrationProgress, now: Date) -> String {
        var summary = "Hydration, \(progress.percent) percent of today's goal"
        if let due = model.dueAt {
            let minutes = Int((HydrationReminder.secondsUntil(due, now: now) / 60).rounded(.up))
            summary += ", next reminder in \(minutes) minutes"
        }
        return summary
    }
}
