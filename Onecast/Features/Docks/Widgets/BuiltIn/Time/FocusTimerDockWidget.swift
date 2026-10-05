import OnecastPluginKit
import SwiftUI

/// A Pomodoro timer whose running phase is an end date, so it carries on across a relaunch.
final class FocusTimerDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Focus Timer", subtitle: "Pomodoro focus and break rounds", icon: "timer",
        category: "Time", sizes: [.compact, .wide, .expanded])

    static let preferences = [
        PluginPreference(
            name: "focusMinutes", title: "Focus (minutes)", placeholder: "25",
            defaultValue: .string("25")),
        PluginPreference(
            name: "shortBreakMinutes", title: "Short break (minutes)", placeholder: "5",
            defaultValue: .string("5")),
        PluginPreference(
            name: "longBreakMinutes", title: "Long break (minutes)", placeholder: "15",
            defaultValue: .string("15")),
        PluginPreference(
            name: "rounds", title: "Rounds before a long break", placeholder: "4",
            defaultValue: .string("4")),
        PluginPreference(
            name: "autoStart", title: "Start the next phase automatically", kind: .checkbox,
            defaultValue: .bool(false)),
        PluginPreference(
            name: "sound", title: "Play a sound when a phase ends", kind: .checkbox,
            defaultValue: .bool(true))
    ]

    private let model = FocusTimerModel()

    func tile(context: DockWidgetContext) -> AnyView {
        model.bind(context.preferences)
        return AnyView(FocusTimerTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        model.bind(context.preferences)
        return AnyView(FocusTimerPopoverView(model: model, context: context))
    }

    func didRemove() {
        model.release()
    }
}

private extension PomodoroPhase {
    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    var tint: Color {
        self == .focus ? Theme.Colors.progress : Theme.Colors.success
    }
}

/// The numbers a tile and its popover both draw, taken from one moment.
@MainActor
private struct FocusTimerReading {
    let phase: PomodoroPhase
    let status: PomodoroState.Status
    let round: Int
    let rounds: Int
    let remaining: TimeInterval
    let progress: Double

    init(state: PomodoroState, settings: PomodoroSettings, date: Date) {
        phase = state.phase
        status = state.status
        round = min(state.round, settings.rounds)
        rounds = settings.rounds
        remaining = state.remaining(now: date, settings: settings)
        progress = state.progress(now: date, settings: settings)
    }

    var time: String { TimeFormat.duration(remaining, rounding: .up) }
    var tint: Color { phase.tint }
    var isRunning: Bool { status == .running }

    var statusText: String {
        switch status {
        case .ready: "Ready"
        case .running: "Running"
        case .paused: "Paused"
        }
    }

    var primaryActionTitle: String {
        switch status {
        case .ready: "Start"
        case .running: "Pause"
        case .paused: "Resume"
        }
    }

    /// The time left under `label`, with the phase's progress as a bar.
    func lines(label: String, caption: String? = nil) -> TimeTileStack.Lines {
        TimeTileStack.Lines(
            label: label, tint: tint, value: time,
            valueColor: isRunning ? Theme.Colors.textPrimary : Theme.Colors.textSecondary,
            bar: progress, caption: caption)
    }
}

private struct FocusTimerTileView: View {
    let model: FocusTimerModel
    let context: DockWidgetContext

    var body: some View {
        let metrics = TimeTileMetrics(context)
        let settings = FocusTimerModel.settings(context.preferences)
        TimeLiveView(granularity: .second) { date in
            let reading = FocusTimerReading(state: model.state, settings: settings, date: date)
            TimeTileContent(metrics) {
                switch metrics.size {
                case .compact:
                    TimeTileStack(lines: reading.lines(label: reading.phase.title), metrics: metrics)
                case .wide:
                    TimeTileStack(
                        lines: reading.lines(
                            label: metrics.isVertical
                                ? reading.phase.title
                                : "\(reading.phase.title) · \(reading.round)/\(reading.rounds)",
                            caption: metrics.isVertical ? "Round \(reading.round)/\(reading.rounds)" : nil),
                        metrics: metrics)
                case .expanded:
                    TimeAxisStack(isVertical: metrics.isVertical, spacing: metrics.spacing) {
                        TimeTileStack(lines: reading.lines(label: reading.phase.title), metrics: metrics)
                        TimeTileStack(
                            lines: .init(
                                label: "Round", tint: reading.tint,
                                value: "\(reading.round)/\(reading.rounds)",
                                caption: reading.statusText),
                            metrics: metrics)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One dot per round of the cycle, filled up to the current one.
private struct FocusTimerRoundDots: View {
    let round: Int
    let rounds: Int
    let tint: Color
    let dot: CGFloat

    var body: some View {
        HStack(spacing: dot / 2) {
            ForEach(1...rounds, id: \.self) { index in
                Circle()
                    .fill(index <= round ? tint : Theme.Colors.separator)
                    .frame(width: dot, height: dot)
            }
        }
    }
}

private struct FocusTimerPopoverView: View {
    let model: FocusTimerModel
    let context: DockWidgetContext

    private static let ringSize: CGFloat = 140
    private static let ringLine: CGFloat = 10

    var body: some View {
        let settings = FocusTimerModel.settings(context.preferences)
        TimeLiveView(granularity: .second) { date in
            let reading = FocusTimerReading(state: model.state, settings: settings, date: date)
            VStack(spacing: Theme.Spacing.xl) {
                ZStack {
                    TimeRingView(
                        fraction: reading.progress, lineWidth: Self.ringLine, tint: reading.tint,
                        sweeps: reading.isRunning)
                    VStack(spacing: Theme.Spacing.xxs) {
                        Text(reading.time).timeFigure(Theme.Typography.calcResult)
                        Text(reading.phase.title)
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(reading.tint)
                    }
                }
                .frame(width: Self.ringSize, height: Self.ringSize)
                VStack(spacing: Theme.Spacing.sm) {
                    FocusTimerRoundDots(
                        round: reading.round, rounds: reading.rounds, tint: reading.tint,
                        dot: Theme.Spacing.md)
                    Text("Round \(reading.round) of \(reading.rounds) · \(reading.statusText)")
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                TimeActionButton(
                    title: reading.primaryActionTitle,
                    symbol: reading.isRunning ? "pause.fill" : "play.fill", isProminent: true
                ) {
                    model.toggle()
                }
                HStack(spacing: Theme.Spacing.md) {
                    TimeActionButton(title: "Reset", symbol: "arrow.counterclockwise") { model.reset() }
                    TimeActionButton(title: "Skip", symbol: "forward.end.fill") { model.skip() }
                }
            }
            .padding(TimeTileMetrics.Popover.padding)
            .frame(width: TimeTileMetrics.Popover.width)
        }
    }
}
