import OnecastPluginKit
import SwiftUI

/// The time, and the date once there is room: digital or analog, in the system's 12/24-hour form.
final class ClockDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Clock", subtitle: "The time and today's date", icon: "clock", category: "Time",
        sizes: [.compact, .wide, .expanded])

    static let preferences = [
        PluginPreference(
            name: "style", title: "Style", kind: .dropdown,
            options: [
                PluginPreference.Option(title: "Digital", value: "digital"),
                PluginPreference.Option(title: "Analog", value: "analog")
            ], defaultValue: .string("digital")),
        PluginPreference(
            name: "showSeconds", title: "Show seconds", kind: .checkbox, defaultValue: .bool(false))
    ]

    private var lease: TimeTickLease?
    private var preferences: DockWidgetPreferences?

    init() {
        lease = TimeTickLease(needsSeconds: { [weak self] in
            self?.preferences?.bool("showSeconds") ?? false
        })
    }

    func tile(context: DockWidgetContext) -> AnyView {
        preferences = context.preferences
        return AnyView(ClockTileView(context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(ClockPopoverView())
    }

    func didRemove() {
        lease?.release()
        lease = nil
    }
}

private enum ClockStyle: String {
    case digital, analog

    init(_ preferences: DockWidgetPreferences) {
        self = ClockStyle(rawValue: preferences.string("style") ?? "") ?? .digital
    }
}

private struct ClockTileView: View {
    let context: DockWidgetContext

    var body: some View {
        let metrics = TimeTileMetrics(context)
        let style = ClockStyle(context.preferences)
        let showsSeconds = context.preferences.bool("showSeconds")
        TimeLiveView(granularity: showsSeconds ? .second : .minute) { date in
            TimeTileContent(metrics) {
                switch style {
                case .digital: DigitalClock(date: date, showsSeconds: showsSeconds, metrics: metrics)
                case .analog: AnalogClock(date: date, showsSeconds: showsSeconds, metrics: metrics)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DigitalClock: View {
    let date: Date
    let showsSeconds: Bool
    let metrics: TimeTileMetrics

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let zone = calendar.timeZone
        let parts = TimeFormat.clockParts(date, calendar: calendar, zone: zone, showSeconds: showsSeconds)
        let full = TimeFormat.clock(date, calendar: calendar, zone: zone, showSeconds: showsSeconds)
        let week = "Week \(TimeFormat.weekNumber(date, calendar: calendar))"
        switch metrics.size {
        case .compact:
            TimeTileStack(
                lines: .init(
                    label: TimeFormat.weekday(date, calendar: calendar), value: parts.time,
                    valueRole: .hero, caption: parts.period.isEmpty ? nil : parts.period),
                metrics: metrics)
        case .wide:
            TimeTileStack(
                lines: .init(
                    label: metrics.isVertical
                        ? TimeFormat.weekday(date, calendar: calendar)
                        : TimeFormat.date(date, calendar: calendar, long: false),
                    value: full,
                    valueRole: .hero, caption: week),
                metrics: metrics)
        case .expanded:
            TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
                TimeTileStack(
                    lines: .init(
                        label: metrics.isVertical
                            ? TimeFormat.weekday(date, calendar: calendar)
                            : TimeFormat.date(date, calendar: calendar, long: true),
                        value: full,
                        valueRole: .hero),
                    metrics: metrics)
                TimeTileStack(
                    lines: .init(
                        label: week, value: "\(TimeFormat.dayOfYear(date, calendar: calendar))",
                        caption: "day of the year"),
                    metrics: metrics)
            }
        }
    }
}

private struct AnalogClock: View {
    let date: Date
    let showsSeconds: Bool
    let metrics: TimeTileMetrics

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let face = TimeAnalogFaceView(
            angles: TimeTick.angles(at: date, calendar: calendar), showsSecondHand: showsSeconds)
        switch metrics.size {
        case .compact:
            face
        case .wide:
            TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
                face
                TimeTileStack(
                    lines: .init(
                        label: TimeFormat.weekday(date, calendar: calendar),
                        value: TimeFormat.day(date, calendar: calendar),
                        caption: TimeFormat.monthDay(date, calendar: calendar)),
                    metrics: metrics)
            }
        case .expanded:
            TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
                face
                TimeTileStack(
                    lines: .init(
                        label: metrics.isVertical
                            ? TimeFormat.weekday(date, calendar: calendar)
                            : TimeFormat.date(date, calendar: calendar, long: true),
                        value: TimeFormat.clock(
                            date, calendar: calendar, zone: calendar.timeZone, showSeconds: showsSeconds),
                        caption: "Week \(TimeFormat.weekNumber(date, calendar: calendar))"),
                    metrics: metrics)
            }
        }
    }
}

/// A larger clock with the full date and the week number; it ticks each second while it is open.
private struct ClockPopoverView: View {
    var body: some View {
        TimelineView(.everySecond) { timeline in
            let calendar = Calendar.autoupdatingCurrent
            let date = timeline.date
            VStack(spacing: Theme.Spacing.lg) {
                TimeAnalogFaceView(
                    angles: TimeTick.angles(at: date, calendar: calendar), showsSecondHand: true
                )
                .frame(width: TimeTileMetrics.Popover.clockFace, height: TimeTileMetrics.Popover.clockFace)
                Text(
                    TimeFormat.clock(
                        date, calendar: calendar, zone: calendar.timeZone, showSeconds: true)
                )
                .timeFigure(Theme.Typography.calcResult)
                Text(TimeFormat.date(date, calendar: calendar, long: true))
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Week \(TimeFormat.weekNumber(date, calendar: calendar))")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(TimeTileMetrics.Popover.padding)
            .frame(width: TimeTileMetrics.Popover.width)
        }
    }
}
