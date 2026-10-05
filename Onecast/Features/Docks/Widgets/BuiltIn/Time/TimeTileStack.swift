import SwiftUI

/// One centred cell: a dot-and-label header, a bold value, an optional thin bar, then captions.
struct TimeTileStack: View {
    struct Lines {
        var label: String?
        var tint: Color = Theme.Colors.progress
        let value: String
        var valueColor: Color = Theme.Colors.textPrimary
        var valueRole: TimeTileMetrics.Role = .display
        /// Progress through something, 0...1, drawn as a bar under the value.
        var bar: Double?
        var caption: String?
        var footer: String?
        /// Puts the label under the value, as a stacked metric reads: `24%` over `● CPU`.
        var labelFollowsValue = false
    }

    let lines: Lines
    let metrics: TimeTileMetrics

    var body: some View {
        VStack(spacing: metrics.spacing / 2) {
            if let label = lines.label, !lines.labelFollowsValue { header(label) }
            Text(lines.value)
                .timeFigure(metrics.font(lines.valueRole, weight: .bold), color: lines.valueColor)
            if let bar = lines.bar {
                TimeBarView(fraction: bar, height: metrics.barHeight, tint: lines.tint)
                    .padding(.horizontal, metrics.spacing)
            }
            if let label = lines.label, lines.labelFollowsValue { header(label) }
            if let caption = lines.caption { secondary(caption) }
            if let footer = lines.footer { secondary(footer) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ label: String) -> some View {
        TimeTileHeader(label: label, tint: lines.tint, metrics: metrics)
    }

    private func secondary(_ text: String) -> some View {
        Text(text).timeFigure(metrics.font(.caption), color: Theme.Colors.textSecondary)
    }
}
