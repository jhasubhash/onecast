import SwiftUI

/// One reading in the dock's tile style: a bold value, an accent dot with its label, a caption.
struct SystemMetricReadout: View {
    enum LabelPosition {
        case above, below
    }

    let label: String
    let tint: Color
    let value: String
    var caption: String?
    var labelPosition = LabelPosition.below
    let metrics: SystemTileMetrics

    var body: some View {
        VStack(spacing: metrics.spacing / 2) {
            if labelPosition == .above { header }
            Text(value)
                .font(metrics.font(.display, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if labelPosition == .below { header }
            if let caption {
                Text(caption)
                    .font(metrics.font(.caption, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([value, caption].compactMap { $0 }.joined(separator: ", "))
    }

    private var header: some View {
        HStack(spacing: metrics.spacing) {
            Circle().fill(tint).frame(width: metrics.dotSize, height: metrics.dotSize)
            Text(label)
                .font(metrics.font(.caption, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
