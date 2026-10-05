import OnecastPluginKit
import SwiftUI

/// Days, hours and minutes left until an ISO date or a plain-words date such as "Dec 25 9am".
final class CountdownDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Countdown", subtitle: "Time left until a date", icon: "hourglass", category: "Time",
        sizes: [.compact, .wide, .expanded])

    static let preferences = [
        PluginPreference(name: "title", title: "Title", placeholder: "Launch day"),
        PluginPreference(
            name: "target", title: "Date and time",
            description: "An ISO date such as 2026-12-25 18:30, or words such as “Dec 25 9am”.",
            placeholder: "2026-12-25 18:30")
    ]

    private let model = CountdownModel()

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(CountdownTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(CountdownPopoverView(model: model, context: context))
    }

    func didRemove() {
        model.release()
    }
}

/// The title and what is left until the target, taken from one moment.
@MainActor
private struct CountdownReading {
    let title: String
    let target: Date?
    let breakdown: TimeCountdown.Breakdown?

    init(model: CountdownModel, preferences: DockWidgetPreferences, date: Date) {
        title = preferences.string("title") ?? "Countdown"
        target = model.target(preferences, now: date)
        breakdown = target.map {
            TimeCountdown.breakdown(from: date, to: $0, calendar: .autoupdatingCurrent)
        }
    }

    var isPast: Bool { breakdown?.isPast ?? false }
    var accent: Color { isPast ? Theme.Colors.success : Theme.Colors.warning }

    /// The big figure: what is left, or that it is over.
    var headline: String {
        guard let breakdown else { return "—" }
        return breakdown.isPast ? "Done" : breakdown.summary
    }

    /// The target's date under the figure; wider tiles add its time.
    func targetText(showsTime: Bool) -> String? {
        guard let target else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        return showsTime
            ? TimeFormat.dateTime(target, calendar: calendar)
            : TimeFormat.monthDay(target, calendar: calendar)
    }

    func lines(showsTime: Bool) -> TimeTileStack.Lines {
        TimeTileStack.Lines(
            label: title, tint: accent, value: headline, caption: targetText(showsTime: showsTime))
    }
}

private struct CountdownTileView: View {
    let model: CountdownModel
    let context: DockWidgetContext

    var body: some View {
        let metrics = TimeTileMetrics(context)
        TimeLiveView(granularity: .second) { date in
            let reading = CountdownReading(model: model, preferences: context.preferences, date: date)
            TimeTileContent(metrics) {
                if let breakdown = reading.breakdown {
                    switch metrics.size {
                    case .compact:
                        TimeTileStack(lines: reading.lines(showsTime: false), metrics: metrics)
                    case .wide:
                        TimeTileStack(
                            lines: reading.lines(showsTime: !metrics.isVertical), metrics: metrics)
                    case .expanded:
                        CountdownExpanded(reading: reading, breakdown: breakdown, metrics: metrics)
                    }
                } else {
                    TimeTileStack(
                        lines: .init(
                            label: "Countdown", tint: Theme.Colors.warning, value: "—",
                            valueColor: Theme.Colors.textTertiary,
                            caption: metrics.isCompact ? nil : "Set a date in settings"),
                        metrics: metrics)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The title and target beside days, hours and minutes, each its own stacked metric.
private struct CountdownExpanded: View {
    let reading: CountdownReading
    let breakdown: TimeCountdown.Breakdown
    let metrics: TimeTileMetrics

    var body: some View {
        TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
            TimeTileStack(lines: reading.lines(showsTime: breakdown.isPast), metrics: metrics)
            if !breakdown.isPast {
                unit(breakdown.days, "days", Theme.Colors.warning)
                unit(breakdown.hours, "hours", Theme.Colors.progress)
                unit(breakdown.minutes, "min", Theme.Colors.success)
            }
        }
    }

    private func unit(_ value: Int, _ label: String, _ tint: Color) -> some View {
        TimeTileStack(
            lines: .init(label: label, tint: tint, value: "\(value)", labelFollowsValue: true),
            metrics: metrics)
    }
}

private struct CountdownPopoverView: View {
    let model: CountdownModel
    let context: DockWidgetContext

    var body: some View {
        TimelineView(.everySecond) { timeline in
            let reading = CountdownReading(
                model: model, preferences: context.preferences, date: timeline.date)
            VStack(spacing: Theme.Spacing.lg) {
                Text(reading.title)
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let breakdown = reading.breakdown, let target = reading.target {
                    Text(breakdown.isPast ? "Done" : breakdown.detail)
                        .timeFigure(
                            Theme.Typography.calcResult,
                            color: breakdown.isPast ? Theme.Colors.success : Theme.Colors.textPrimary)
                    Text(
                        (breakdown.isPast ? "Reached " : "Until ")
                            + TimeFormat.dateTime(target, calendar: .autoupdatingCurrent)
                    )
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("No date set, or it could not be read.")
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                TimeActionButton(title: "Edit in Settings", symbol: "gearshape") {
                    context.actions.openSettings()
                }
            }
            .padding(TimeTileMetrics.Popover.padding)
            .frame(width: TimeTileMetrics.Popover.width)
        }
    }
}
