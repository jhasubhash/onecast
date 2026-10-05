import SwiftUI

/// A small accent dot and a short secondary label, truncated with an ellipsis when it runs long.
struct TimeTileHeader: View {
    let label: String
    let tint: Color
    let metrics: TimeTileMetrics

    var body: some View {
        HStack(spacing: metrics.spacing / 2) {
            Circle()
                .fill(tint)
                .frame(width: metrics.dot, height: metrics.dot)
            Text(label)
                .font(metrics.font(.caption, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
