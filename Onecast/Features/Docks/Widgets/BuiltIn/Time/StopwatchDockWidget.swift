import OnecastPluginKit
import SwiftUI

/// Start, stop, lap and reset, with laps in the popover; a running watch outlives a relaunch.
final class StopwatchDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Stopwatch", subtitle: "Time anything, with laps", icon: "stopwatch", category: "Time",
        sizes: [.compact, .wide, .expanded])

    static let preferences: [PluginPreference] = []

    private let model = StopwatchModel()

    func tile(context: DockWidgetContext) -> AnyView {
        model.bind(context.preferences)
        return AnyView(StopwatchTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        model.bind(context.preferences)
        return AnyView(StopwatchPopoverView(model: model))
    }

    func didRemove() {
        model.release()
    }
}

private struct StopwatchTileView: View {
    let model: StopwatchModel
    let context: DockWidgetContext

    var body: some View {
        let metrics = TimeTileMetrics(context)
        TimeLiveView(granularity: .second) { date in
            let state = model.state
            let lapCount = state.laps.count
            let main = TimeTileStack.Lines(
                label: Self.status(state), tint: Self.tint(state),
                value: TimeFormat.stopwatch(state.elapsed(now: date), fractionDigits: 0),
                valueColor: state.isRunning ? Theme.Colors.textPrimary : Theme.Colors.textSecondary,
                caption: lapCount == 0 || metrics.size == .expanded ? nil : "Lap \(lapCount + 1)")
            TimeTileContent(metrics) {
                if metrics.size == .expanded {
                    TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
                        TimeTileStack(lines: main, metrics: metrics)
                        TimeTileStack(
                            lines: .init(
                                label: "Lap \(lapCount + 1)", tint: Self.tint(state),
                                value: TimeFormat.stopwatch(state.currentSplit(now: date), fractionDigits: 0),
                                caption: lapCount == 0 ? "No laps yet" : "\(lapCount) laps"),
                            metrics: metrics)
                    }
                } else {
                    TimeTileStack(lines: main, metrics: metrics)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func status(_ state: StopwatchState) -> String {
        if state.isRunning { return "Running" }
        return state.isPristine ? "Stopwatch" : "Stopped"
    }

    private static func tint(_ state: StopwatchState) -> Color {
        if state.isRunning { return Theme.Colors.success }
        return state.isPristine ? Theme.Colors.textTertiary : Theme.Colors.warning
    }
}

private struct StopwatchPopoverView: View {
    /// How often the open popover redraws its tenths of a second.
    private static let tenthsInterval: TimeInterval = 0.1

    let model: StopwatchModel

    var body: some View {
        let state = model.state
        let schedule = AnimationTimelineSchedule(
            minimumInterval: Self.tenthsInterval, paused: !state.isRunning)
        VStack(spacing: Theme.Spacing.xl) {
            TimelineView(schedule) { timeline in
                Text(TimeFormat.stopwatch(state.elapsed(now: timeline.date), fractionDigits: 1))
                    .timeFigure(Font.largeTitle.weight(.semibold))
            }
            HStack(spacing: Theme.Spacing.md) {
                if state.isRunning {
                    TimeActionButton(title: "Lap", symbol: "flag.fill") { model.lap() }
                } else {
                    TimeActionButton(title: "Reset", symbol: "arrow.counterclockwise") { model.reset() }
                        .disabled(state.isPristine)
                }
                TimeActionButton(
                    title: state.isRunning ? "Stop" : "Start",
                    symbol: state.isRunning ? "pause.fill" : "play.fill", isProminent: true
                ) {
                    model.toggle()
                }
            }
            if !state.laps.isEmpty {
                StopwatchLapList(state: state)
            }
        }
        .padding(TimeTileMetrics.Popover.padding)
        .frame(width: TimeTileMetrics.Popover.width)
    }
}

/// Newest lap first, with the quickest and slowest splits tinted once there are two to compare.
private struct StopwatchLapList: View {
    private static let totalColumnWidth: CGFloat = 64

    let state: StopwatchState

    var body: some View {
        let extremes = state.fastestAndSlowest
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(state.laps.reversed()) { lap in
                    HStack {
                        Text("Lap \(lap.number)")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer(minLength: Theme.Spacing.md)
                        Text(TimeFormat.stopwatch(lap.split, fractionDigits: 2))
                            .foregroundStyle(tint(lap.number, extremes))
                        Text(TimeFormat.stopwatch(lap.total, fractionDigits: 0))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(minWidth: Self.totalColumnWidth, alignment: .trailing)
                    }
                    .font(Theme.Typography.rowTrailing.monospacedDigit())
                }
            }
        }
        .frame(maxHeight: TimeTileMetrics.Popover.listMaxHeight)
    }

    private func tint(_ number: Int, _ extremes: (fastest: Int, slowest: Int)?) -> Color {
        guard let extremes else { return Theme.Colors.textPrimary }
        if number == extremes.fastest { return Theme.Colors.success }
        if number == extremes.slowest { return Theme.Colors.destructive }
        return Theme.Colors.textPrimary
    }
}
