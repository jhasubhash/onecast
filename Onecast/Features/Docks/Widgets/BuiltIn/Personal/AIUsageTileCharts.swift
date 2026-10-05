import SwiftUI

/// A ring filled clockwise from the top in a soft gradient; progress outside 0...1 clamps.
struct AIUsageRing: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    private static let gradientFloor = 0.35

    var body: some View {
        let share = min(max(progress, 0), 1)
        ZStack {
            Circle().stroke(Theme.Colors.controlSurface, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: share)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(Self.gradientFloor), tint], center: .center,
                        startAngle: .degrees(0), endAngle: .degrees(360 * max(share, 0.02))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// A rounded track filled from the leading edge in a soft gradient; progress clamps to 0...1.
struct AIUsageBar: View {
    let progress: Double
    let tint: Color

    private static let gradientFloor = 0.45

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.controlSurface)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(Self.gradientFloor), tint], startPoint: .leading,
                            endPoint: .trailing)
                    )
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
    }
}

/// A column of dots per day, oldest first, today in full colour, each a share of the busiest day.
struct AIUsageDayBars: View {
    let days: [Double]
    let tint: Color

    private static let rows = 5
    private static let dotScale = 0.72
    private static let pastOpacity = 0.7
    private static let emptyOpacity = 0.14

    var body: some View {
        Canvas { context, size in
            guard !days.isEmpty, size.width > 0, size.height > 0 else { return }
            let slot = size.width / CGFloat(days.count)
            let rowHeight = size.height / CGFloat(Self.rows)
            let diameter = max(min(slot, rowHeight) * Self.dotScale, 0.5)
            for (column, share) in days.enumerated() {
                let clamped = min(max(share, 0), 1)
                let filled = clamped > 0 ? max(1, Int((clamped * Double(Self.rows)).rounded(.up))) : 0
                let color = column == days.count - 1 ? tint : tint.opacity(Self.pastOpacity)
                let x = slot * (CGFloat(column) + 0.5)
                for row in 0..<Self.rows {
                    let y = size.height - rowHeight * (CGFloat(row) + 0.5)
                    let dot = CGRect(
                        x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
                    context.fill(
                        Path(ellipseIn: dot),
                        with: .color(row < filled ? color : tint.opacity(Self.emptyOpacity)))
                }
            }
        }
    }
}
