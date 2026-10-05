import OnecastPluginKit
import SwiftUI

/// How far through the day, week, month and year it is, each as a bar with its percentage.
final class TimeProgressDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Time Progress", subtitle: "How far through the day, week, month and year",
        icon: "chart.bar.fill", category: "Time", sizes: [.compact, .wide, .expanded])

    static let preferences = TimeProgress.allCases.map { period in
        PluginPreference(
            name: period.rawValue, title: "Show \(period.title.lowercased())", kind: .checkbox,
            defaultValue: .bool(true))
    }

    private var lease: TimeTickLease? = TimeTickLease()

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(TimeProgressTileView(context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(TimeProgressPopoverView())
    }

    func didRemove() {
        lease?.release()
        lease = nil
    }
}

private extension TimeProgress {
    var tint: Color {
        switch self {
        case .day: Theme.Colors.progress
        case .week: Theme.Colors.success
        case .month: Theme.Colors.warning
        case .year: Color.purple
        }
    }

    /// The periods the user turned on, or the day alone when every box is off.
    static func chosen(_ preferences: DockWidgetPreferences) -> [TimeProgress] {
        let chosen = allCases.filter { preferences.bool($0.rawValue) }
        return chosen.isEmpty ? [.day] : chosen
    }
}

private struct TimeProgressTileView: View {
    let context: DockWidgetContext

    var body: some View {
        let metrics = TimeTileMetrics(context)
        let periods = TimeProgress.chosen(context.preferences).prefix(metrics.cells)
        TimeLiveView(granularity: .minute) { date in
            TimeTileContent(metrics) {
                TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
                    ForEach(periods, id: \.self) { period in
                        let measure = period.measure(at: date, calendar: .autoupdatingCurrent)
                        TimeTileStack(
                            lines: .init(
                                label: period.title, tint: period.tint, value: "\(measure.percent)%",
                                bar: measure.fraction, labelFollowsValue: true),
                            metrics: metrics)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// All four periods with what is left of each.
private struct TimeProgressPopoverView: View {
    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let calendar = Calendar.autoupdatingCurrent
            VStack(spacing: Theme.Spacing.xl) {
                ForEach(TimeProgress.allCases, id: \.self) { period in
                    let measure = period.measure(at: timeline.date, calendar: calendar)
                    VStack(spacing: Theme.Spacing.sm) {
                        HStack {
                            Text(period.title)
                                .font(Theme.Typography.rowTitle)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer(minLength: Theme.Spacing.md)
                            Text("\(measure.percent)%")
                                .font(Theme.Typography.rowTitle.monospacedDigit())
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        TimeBarView(
                            fraction: measure.fraction, height: Theme.Size.volumeTrackHeight,
                            tint: period.tint)
                        Text(left(measure.remaining, now: timeline.date, calendar: calendar))
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(TimeTileMetrics.Popover.padding)
            .frame(width: TimeTileMetrics.Popover.width)
        }
    }

    private func left(_ remaining: TimeInterval, now: Date, calendar: Calendar) -> String {
        let end = now.addingTimeInterval(remaining)
        return TimeCountdown.breakdown(from: now, to: end, calendar: calendar).summary + " left"
    }
}
