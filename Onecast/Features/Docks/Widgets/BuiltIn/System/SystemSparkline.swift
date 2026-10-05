import SwiftUI

/// A history as a line over a faint fill, oldest first; a short series grows in from the right.
struct SystemSparkline: View {
    let values: [Double]
    let capacity: Int
    let tint: Color
    let lineWidth: CGFloat

    init(series: SystemSeries, ceiling: Double, tint: Color, lineWidth: CGFloat) {
        values = series.normalized(ceiling: ceiling)
        capacity = series.capacity
        self.tint = tint
        self.lineWidth = lineWidth
    }

    private var fill: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack {
            SparklineShape(values: values, capacity: capacity, closed: true).fill(fill)
            SparklineShape(values: values, capacity: capacity, closed: false)
                .stroke(
                    tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct SparklineShape: Shape {
    let values: [Double]
    let capacity: Int
    /// Drops to the baseline at both ends, so the shape can be filled.
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, capacity > 1 else { return path }
        let step = rect.width / CGFloat(capacity - 1)
        let start = rect.maxX - step * CGFloat(values.count - 1)
        func point(_ index: Int) -> CGPoint {
            let level = CGFloat(min(max(values[index], 0), 1))
            return CGPoint(x: start + step * CGFloat(index), y: rect.maxY - rect.height * level)
        }
        path.move(to: closed ? CGPoint(x: start, y: rect.maxY) : point(0))
        if closed { path.addLine(to: point(0)) }
        for index in 1..<values.count { path.addLine(to: point(index)) }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
