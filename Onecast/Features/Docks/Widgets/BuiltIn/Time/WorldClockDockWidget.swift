import OnecastPluginKit
import SwiftUI

/// The time in up to four other cities, each with how far its date and clock sit from the Mac's.
final class WorldClockDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "World Clock", subtitle: "The time in other cities", icon: "globe", category: "Time",
        sizes: [.compact, .wide, .expanded])

    static let preferences = [
        PluginPreference(
            name: "zones", title: "Cities",
            description: "Up to four, separated by commas: city names or IANA identifiers.",
            placeholder: "New York, London, Asia/Tokyo",
            defaultValue: .string("New York, London, Tokyo, Sydney"))
    ]

    private var lease: TimeTickLease? = TimeTickLease()

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(WorldClockTileView(context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(WorldClockPopoverView(context: context))
    }

    func didRemove() {
        lease?.release()
        lease = nil
    }
}

private struct WorldClockTileView: View {
    let context: DockWidgetContext

    var body: some View {
        let metrics = TimeTileMetrics(context)
        let clocks = Array(
            TimeWorldClock.resolve(context.preferences.string("zones") ?? "").prefix(metrics.cells))
        TimeLiveView(granularity: .minute) { date in
            TimeTileContent(metrics) {
                if clocks.isEmpty {
                    WorldClockEmptyState(metrics: metrics)
                } else {
                    TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
                        ForEach(clocks.indices, id: \.self) { index in
                            WorldClockCell(
                                clock: clocks[index], tint: Self.tint(index), date: date, metrics: metrics)
                        }
                    }
                }
            }
        }
    }

    /// Each city keeps its own accent, so two cells side by side read apart at a glance.
    private static func tint(_ index: Int) -> Color {
        [Color.teal, Theme.Colors.warning, Color.purple, Color.pink][index % 4]
    }
}

private struct WorldClockCell: View {
    let clock: TimeWorldClock
    let tint: Color
    let date: Date
    let metrics: TimeTileMetrics

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let days = clock.dayOffset(at: date, home: calendar.timeZone)
        let ahead = clock.secondsAhead(at: date, home: calendar.timeZone)
        let parts = TimeFormat.clockParts(date, calendar: calendar, zone: clock.zone, showSeconds: false)
        let relation = days == 0 ? TimeFormat.hourOffset(ahead) : TimeFormat.dayOffset(days)
        TimeTileStack(
            lines: .init(
                label: clock.label, tint: tint, value: parts.time,
                caption: [parts.period, relation].filter { !$0.isEmpty }.joined(separator: " · ")),
            metrics: metrics
        )
        .accessibilityElement(children: .combine)
    }
}

/// What the tile says while no city resolves, so a typo is visible rather than a blank tile.
private struct WorldClockEmptyState: View {
    let metrics: TimeTileMetrics

    var body: some View {
        TimeTileStack(
            lines: .init(
                label: "World Clock", tint: Color.teal, value: "—",
                valueColor: Theme.Colors.textTertiary,
                caption: metrics.isCompact ? nil : "Add cities in settings"),
            metrics: metrics)
    }
}

/// Every city with its time, date offset and hour offset; empty text points at the settings.
private struct WorldClockPopoverView: View {
    let context: DockWidgetContext

    var body: some View {
        let clocks = TimeWorldClock.resolve(context.preferences.string("zones") ?? "")
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if clocks.isEmpty {
                Text("No cities yet")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Name up to four cities, or IANA identifiers such as Asia/Tokyo.")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TimeActionButton(title: "Open Settings", symbol: "gearshape") {
                    context.actions.openSettings()
                }
            } else {
                TimelineView(.everyMinute) { timeline in
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        ForEach(clocks) { clock in
                            WorldClockRow(clock: clock, date: timeline.date)
                        }
                    }
                }
            }
        }
        .padding(TimeTileMetrics.Popover.padding)
        .frame(width: TimeTileMetrics.Popover.width, alignment: .leading)
    }
}

private struct WorldClockRow: View {
    let clock: TimeWorldClock
    let date: Date

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let days = clock.dayOffset(at: date, home: calendar.timeZone)
        let ahead = clock.secondsAhead(at: date, home: calendar.timeZone)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(clock.label)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(TimeFormat.dayOffset(days)) · \(TimeFormat.hourOffset(ahead))")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            Text(TimeFormat.clock(date, calendar: calendar, zone: clock.zone, showSeconds: false))
                .font(Theme.Typography.calcResult)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
