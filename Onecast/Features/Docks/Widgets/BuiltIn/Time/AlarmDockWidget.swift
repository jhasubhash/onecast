import OnecastPluginKit
import SwiftUI

/// A daily alarm with a label and an on/off switch that rings with a notification and a sound.
final class AlarmDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Alarm", subtitle: "A daily alarm with snooze", icon: "alarm", category: "Time",
        sizes: [.compact, .wide, .expanded])

    static let preferences = [
        PluginPreference(
            name: "time", title: "Time", description: "Such as 07:30, 7:30 am or 6pm.",
            placeholder: "07:00", defaultValue: .string("07:00")),
        PluginPreference(
            name: "label", title: "Label", placeholder: "Alarm", defaultValue: .string("Alarm")),
        PluginPreference(
            name: "enabled", title: "Alarm is on", kind: .checkbox, defaultValue: .bool(true)),
        PluginPreference(
            name: "sound", title: "Play a sound", kind: .checkbox, defaultValue: .bool(true)),
        PluginPreference(
            name: "snoozeMinutes", title: "Snooze (minutes)", placeholder: "9",
            defaultValue: .string("9"))
    ]

    private let model = AlarmModel()

    func tile(context: DockWidgetContext) -> AnyView {
        model.bind(context.preferences)
        return AnyView(AlarmTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        model.bind(context.preferences)
        return AnyView(AlarmPopoverView(model: model, context: context))
    }

    func didRemove() {
        model.release()
    }
}

/// What a tile and its popover both say about the alarm, taken from one moment.
@MainActor
private struct AlarmReading {
    let alarm: TimeAlarm?
    let isEnabled: Bool
    let isRinging: Bool
    let label: String
    let next: Date?
    let date: Date

    init(model: AlarmModel, preferences: DockWidgetPreferences, date: Date) {
        _ = model.revision
        self.date = date
        alarm = AlarmModel.alarm(preferences)
        isEnabled = preferences.bool("enabled")
        isRinging = model.isRinging
        label = AlarmModel.label(preferences)
        next = model.nextRing(preferences, after: date)
    }

    var symbol: String {
        if isRinging { return "bell.fill" }
        return isEnabled ? "bell" : "bell.slash"
    }

    var tint: Color {
        if isRinging { return Theme.Colors.warning }
        return isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
    }

    /// The alarm's time of day in the system's 12/24-hour form; empty when it cannot be read.
    var time: String {
        let calendar = Calendar.autoupdatingCurrent
        guard let alarm,
            let moment = calendar.date(
                bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: date)
        else { return alarm?.text ?? "—" }
        return TimeFormat.clock(moment, calendar: calendar, zone: calendar.timeZone, showSeconds: false)
    }

    /// `Off`, `in 6h 12m`, or `Ringing`, for the line under the time.
    var status: String {
        if isRinging { return "Ringing" }
        guard isEnabled else { return "Off" }
        guard let next else { return "Set a time" }
        return "in " + TimeCountdown.breakdown(from: date, to: next, calendar: .autoupdatingCurrent).summary
    }

    /// Whole calendar days from today to the next ring, nil while nothing is due.
    var nextDayOffset: Int? {
        guard let next else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        return calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: next)
        ).day
    }

    /// The dot colour: lit while the alarm can ring, quiet while it is off.
    var accent: Color { isEnabled ? Theme.Colors.warning : Theme.Colors.textTertiary }

    /// The tile's one cell: the label, the alarm time, and what the alarm is doing.
    var lines: TimeTileStack.Lines {
        TimeTileStack.Lines(label: label, tint: accent, value: time, valueColor: tint, caption: status)
    }
}

private struct AlarmTileView: View {
    let model: AlarmModel
    let context: DockWidgetContext

    var body: some View {
        let metrics = TimeTileMetrics(context)
        TimeLiveView(granularity: .minute) { date in
            let reading = AlarmReading(model: model, preferences: context.preferences, date: date)
            TimeTileContent(metrics) {
                if metrics.size == .expanded {
                    TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
                        TimeTileStack(lines: reading.lines, metrics: metrics)
                        TimeTileStack(
                            lines: .init(
                                label: "Next ring", tint: reading.accent,
                                value: reading.next == nil
                                    ? "—" : TimeFormat.dayOffset(reading.nextDayOffset ?? 0),
                                valueColor: reading.next == nil
                                    ? Theme.Colors.textTertiary : Theme.Colors.textPrimary,
                                caption: reading.next.map {
                                    metrics.isVertical
                                        ? TimeFormat.monthDay($0, calendar: .autoupdatingCurrent)
                                        : TimeFormat.dateTime($0, calendar: .autoupdatingCurrent)
                                }),
                            metrics: metrics)
                    }
                } else {
                    TimeTileStack(lines: reading.lines, metrics: metrics)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AlarmGlyph: View {
    let reading: AlarmReading
    let size: CGFloat

    var body: some View {
        SymbolImage(name: reading.symbol, size: size)
            .foregroundStyle(reading.tint)
            .symbolEffect(.pulse, isActive: reading.isRinging)
    }
}

private struct AlarmPopoverView: View {
    let model: AlarmModel
    let context: DockWidgetContext

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let reading = AlarmReading(
                model: model, preferences: context.preferences, date: timeline.date)
            VStack(spacing: Theme.Spacing.lg) {
                AlarmGlyph(reading: reading, size: TimeTileMetrics.Popover.glyph)
                Text(reading.label)
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(reading.time).timeFigure(Font.largeTitle.weight(.semibold), color: reading.tint)
                Text(detail(reading))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                buttons(reading)
            }
            .padding(TimeTileMetrics.Popover.padding)
            .frame(width: TimeTileMetrics.Popover.width)
        }
    }

    private func detail(_ reading: AlarmReading) -> String {
        if reading.isRinging { return "Ringing now" }
        guard reading.isEnabled else { return "The alarm is off" }
        guard let next = reading.next else { return "Set a time in settings" }
        let calendar = Calendar.autoupdatingCurrent
        let clock = TimeFormat.clock(next, calendar: calendar, zone: calendar.timeZone, showSeconds: false)
        let prefix = model.snoozeUntil == nil ? "Rings" : "Snoozed until"
        let day = TimeFormat.dayOffset(reading.nextDayOffset ?? 0).lowercased()
        return "\(prefix) \(day) at \(clock) · \(reading.status)"
    }

    @ViewBuilder
    private func buttons(_ reading: AlarmReading) -> some View {
        if reading.isRinging {
            TimeActionButton(
                title: "Snooze \(AlarmModel.snoozeMinutes(context.preferences)) min", symbol: "zzz",
                isProminent: true
            ) {
                model.snooze()
            }
            TimeActionButton(title: "Dismiss", symbol: "xmark") { model.dismiss() }
        } else {
            if model.snoozeUntil != nil {
                TimeActionButton(title: "Cancel snooze", symbol: "xmark") { model.dismiss() }
            }
            TimeActionButton(
                title: reading.isEnabled ? "Turn Off" : "Turn On",
                symbol: reading.isEnabled ? "bell.slash" : "bell", isProminent: !reading.isEnabled
            ) {
                model.toggleEnabled()
            }
            TimeActionButton(title: "Edit in Settings", symbol: "gearshape") {
                context.actions.openSettings()
            }
        }
    }
}
