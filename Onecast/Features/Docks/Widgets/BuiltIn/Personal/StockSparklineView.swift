import SwiftUI

/// A price series drawn as a line over a soft fill, with an optional hover readout.
struct StockSparklineView: View {
    enum Style {
        /// Faint and unmarked, behind a tile's text.
        case backdrop
        case tile
        /// Large enough to hover: a crosshair snaps to the nearest bar and reads its value.
        case chart
    }

    let sparkline: StockSparkline
    let tint: Color
    var style: Style = .tile
    /// The text a hovered bar reads as; only a `.chart` has a hover.
    var readout: (StockSparkline.Point) -> String = { _ in "" }

    @State private var hovered: Int?

    private static let readoutMargin: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let plot = plotRect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(&context, in: plot) }
                if let point = hoveredPoint {
                    readoutLabel(point, plot: plot, width: proxy.size.width)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard style == .chart else { return }
                switch phase {
                case .active(let location):
                    let fraction = plot.width > 0 ? (location.x - plot.minX) / plot.width : 0
                    hovered = sparkline.nearestIndex(toX: fraction)
                case .ended:
                    hovered = nil
                }
            }
        }
    }

    private var hoveredPoint: StockSparkline.Point? {
        guard let hovered, sparkline.points.indices.contains(hovered) else { return nil }
        return sparkline.points[hovered]
    }

    private var lineWidth: CGFloat { style == .backdrop ? 1.5 : 2 }
    private var markerRadius: CGFloat { style == .chart ? 4 : 3 }

    /// The line's room, inset so its stroke and the end marker are never clipped.
    private func plotRect(in size: CGSize) -> CGRect {
        let inset = markerRadius * 2
        return CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    }

    private func position(_ point: StockSparkline.Point, in plot: CGRect) -> CGPoint {
        CGPoint(x: plot.minX + point.x * plot.width, y: plot.maxY - point.y * plot.height)
    }

    private func draw(_ context: inout GraphicsContext, in plot: CGRect) {
        guard sparkline.isDrawable else { return }
        let positions = sparkline.points.map { position($0, in: plot) }
        guard let first = positions.first, let last = positions.last else { return }

        if style != .backdrop, let baseline = sparkline.baseline {
            let y = plot.maxY - baseline * plot.height
            var guide = Path()
            guide.move(to: CGPoint(x: plot.minX, y: y))
            guide.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(
                guide, with: .color(Theme.Colors.textTertiary),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        var line = Path()
        line.addLines(positions)
        var fill = line
        fill.addLine(to: CGPoint(x: last.x, y: plot.maxY + markerRadius))
        fill.addLine(to: CGPoint(x: first.x, y: plot.maxY + markerRadius))
        fill.closeSubpath()
        context.fill(
            fill,
            with: .linearGradient(
                Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]),
                startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
        context.stroke(
            line, with: .color(tint),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        guard style != .backdrop else { return }
        marker(&context, at: hoveredPoint.map { position($0, in: plot) } ?? last, in: plot)
    }

    /// A dot, haloed; while hovering, the crosshair's own dot replaces the end marker.
    private func marker(_ context: inout GraphicsContext, at point: CGPoint, in plot: CGRect) {
        if hoveredPoint != nil {
            var crosshair = Path()
            crosshair.move(to: CGPoint(x: point.x, y: plot.minY))
            crosshair.addLine(to: CGPoint(x: point.x, y: plot.maxY))
            context.stroke(
                crosshair, with: .color(tint.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        let halo = markerRadius * 2
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
            with: .color(tint.opacity(0.25)))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: point.x - markerRadius, y: point.y - markerRadius, width: markerRadius * 2,
                    height: markerRadius * 2)),
            with: .color(tint))
    }

    private func readoutLabel(_ point: StockSparkline.Point, plot: CGRect, width: CGFloat) -> some View {
        let anchor = position(point, in: plot)
        return Text(readout(point))
            .font(Theme.Typography.keyCap)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Capsule().fill(Theme.Colors.controlSurface))
            .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline))
            .fixedSize()
            .modifier(ReadoutPlacement(anchor: anchor, width: width, margin: Self.readoutMargin))
            .allowsHitTesting(false)
    }
}

/// Seats a readout above its bar, held inside the chart's width.
private struct ReadoutPlacement: ViewModifier {
    let anchor: CGPoint
    let width: CGFloat
    let margin: CGFloat
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .offset(
                x: min(max(anchor.x - size.width / 2, 0), max(width - size.width, 0)),
                y: max(anchor.y - size.height - margin, 0))
    }
}
