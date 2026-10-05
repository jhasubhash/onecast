import SwiftUI

/// One cell of the tile, centred as the reference; it sheds parts bottom-up as room runs out.
struct AIUsageCellView: View {
    let cell: AIUsageCell
    let display: PersonalAIUsageDisplay
    let metrics: PersonalTileMetrics
    /// One of several cells: the figure leads and the dot and label sit beneath it.
    let isRow: Bool

    /// Width over height from which a lone cell lays its text beside its chart.
    private static let inlineAspect: CGFloat = 2.0
    private static let ringStroke: CGFloat = 0.07
    private static let barScale: CGFloat = 0.08
    private static let dayBarsScale: CGFloat = 0.24
    private static let smallChartShare: CGFloat = 0.6
    private static let ringMinScale: CGFloat = 0.42
    private static let ringMaxScale: CGFloat = 0.9
    /// A text line and the gap below it, as a share of the tile.
    private static let lineScale: CGFloat = 0.2
    private static let minimumScale: CGFloat = 0.5

    private enum Chart { case none, small, full }
    private enum Tone { case secondary, tertiary }

    /// Which parts one arrangement keeps; the first that fits the cell is drawn.
    private struct Shape {
        var caption = false
        var chart = Chart.none
        var bottom = false
        var tight = false
        var label = true
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                if !isRow, size.width >= size.height * Self.inlineAspect {
                    inline(size)
                } else {
                    ViewThatFits(in: .vertical) {
                        ForEach(Array(shapes.enumerated()), id: \.offset) { _, shape in
                            stack(shape, size)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Arrangements

    /// Richest first. A lone cell leads with its header; one of several leads with its figure.
    private var shapes: [Shape] {
        switch display {
        case .numbers:
            return isRow
                ? [Shape(caption: true, bottom: true), Shape(caption: true), Shape()]
                : [
                    Shape(caption: true, bottom: true), Shape(caption: true),
                    Shape(caption: true, tight: true), Shape(tight: true),
                    Shape(tight: true, label: false),
                ]
        case .rings:
            return isRow
                ? [Shape(chart: .full, bottom: true), Shape(chart: .full)]
                : [
                    Shape(caption: true, chart: .full, bottom: true),
                    Shape(caption: true, chart: .full), Shape(chart: .full),
                    Shape(chart: .full, label: false),
                ]
        case .bars:
            return isRow
                ? [
                    Shape(caption: true, chart: .full, bottom: true),
                    Shape(caption: true, chart: .full), Shape(chart: .full),
                    Shape(chart: .small), Shape(),
                ]
                : [
                    Shape(caption: true, chart: .full, bottom: true),
                    Shape(caption: true, chart: .full), Shape(chart: .full),
                    Shape(chart: .small), Shape(tight: true), Shape(tight: true, label: false),
                ]
        }
    }

    private func stack(_ shape: Shape, _ size: CGSize) -> some View {
        VStack(spacing: shape.tight ? 0 : metrics.spacing / 2) {
            if !isRow, shape.label { header }
            lead(shape, size)
            if shape.caption, display != .rings || !isRow { small(cell.caption, .secondary) }
            if display == .bars, shape.chart != .none { chart(shape.chart) }
            if shape.bottom, !cell.bottoms.isEmpty { bottomLine }
            if isRow { header }
        }
    }

    /// A lone, wide cell: the text beside the chart, so a long tile is not left empty.
    private func inline(_ size: CGSize) -> some View {
        HStack(spacing: metrics.padding) {
            if display == .rings {
                ring(side: min(size.height, metrics.tileLength * Self.ringMaxScale))
                VStack(alignment: .leading, spacing: metrics.spacing / 2) {
                    header
                    small(cell.caption, .secondary)
                    if !cell.bottoms.isEmpty { bottomLine }
                }
            } else {
                VStack(spacing: metrics.spacing / 2) {
                    header
                    value
                    small(cell.caption, .secondary)
                }
                VStack(alignment: .leading, spacing: metrics.spacing / 2) {
                    if display == .bars { chart(.full) }
                    if !cell.bottoms.isEmpty { bottomLine }
                }
            }
        }
    }

    // MARK: - Parts

    /// The figure, or in Rings a ring with the figure inside it.
    @ViewBuilder
    private func lead(_ shape: Shape, _ size: CGSize) -> some View {
        if display == .rings {
            ring(side: ringSide(shape, size))
        } else {
            value
        }
    }

    /// What the text lines leave, never below a size the figure can still be read in.
    private func ringSide(_ shape: Shape, _ size: CGSize) -> CGFloat {
        var lines = 0
        if shape.label { lines += 1 }
        if shape.caption, !isRow { lines += 1 }
        if shape.bottom, !cell.bottoms.isEmpty { lines += 1 }
        let line = metrics.tileLength * Self.lineScale
        let room = size.height - CGFloat(lines) * line - 1
        let side = min(max(room, metrics.tileLength * Self.ringMinScale), size.width)
        return max(min(side, metrics.tileLength * Self.ringMaxScale), 0)
    }

    private func ring(side: CGFloat) -> some View {
        let role: PersonalTileMetrics.Role =
            side >= metrics.tileLength * 0.7 ? .value : side >= metrics.tileLength * 0.5 ? .label : .caption
        return ZStack {
            AIUsageRing(
                progress: cell.progress ?? 0, tint: cell.tint,
                lineWidth: metrics.tileLength * Self.ringStroke)
            Text(cell.figure)
                .font(metrics.font(role, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(Self.minimumScale)
                .padding(metrics.tileLength * Self.ringStroke)
        }
        .frame(width: side, height: side)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            PersonalTileHeader(metrics: metrics, title: cell.label(0), tint: cell.tint)
            PersonalTileHeader(metrics: metrics, title: cell.label(1), tint: cell.tint)
            PersonalTileHeader(metrics: metrics, title: cell.label(2), tint: cell.tint)
            PersonalTileHeader(metrics: metrics, title: cell.label(3), tint: cell.tint)
        }
    }

    /// The longest bottom caption that fits across, so a long one is shortened rather than shrunk.
    private var bottomLine: some View {
        ViewThatFits(in: .horizontal) {
            small(cell.bottom(0), .tertiary).fixedSize(horizontal: true, vertical: false)
            small(cell.bottom(1), .tertiary).fixedSize(horizontal: true, vertical: false)
            small(cell.bottom(2), .tertiary)
        }
    }

    private var value: some View {
        Text(cell.figure)
            .font(metrics.font(.display, weight: .bold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumScale)
    }

    private func small(_ text: String, _ tone: Tone) -> some View {
        Text(text)
            .font(metrics.font(.caption, weight: .medium))
            .foregroundStyle(
                tone == .secondary ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
            )
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumScale)
    }

    @ViewBuilder
    private func chart(_ scale: Chart) -> some View {
        let share = scale == .small ? Self.smallChartShare : 1
        if let progress = cell.progress {
            AIUsageBar(progress: progress, tint: cell.tint)
                .frame(height: metrics.tileLength * Self.barScale)
        } else if let days = cell.days {
            AIUsageDayBars(days: days, tint: cell.tint)
                .frame(height: metrics.tileLength * Self.dayBarsScale * share)
        }
    }
}
