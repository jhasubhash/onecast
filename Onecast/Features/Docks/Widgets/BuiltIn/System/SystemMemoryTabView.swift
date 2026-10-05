import SwiftUI

struct SystemMemoryTabView: View {
    private let sampler = DockWidgetServices.current.activity

    private static let graphHeight: CGFloat = 56
    private static let lineWidth: CGFloat = 2

    var body: some View {
        ScrollView {
            if let memory = sampler.memory {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header(memory)
                    SystemSparkline(
                        series: sampler.memoryHistory, ceiling: 1,
                        tint: SystemTint.pressure(memory.pressure), lineWidth: Self.lineWidth
                    )
                    .frame(height: Self.graphHeight)
                    breakdown(memory)
                    facts(memory)
                }
            } else {
                Text("Measuring…")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func header(_ memory: SystemMemoryUsage) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(SystemFormat.bytes(memory.used))
                .font(Theme.Typography.calcResult.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("of \(SystemFormat.bytes(memory.total)) in use")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private struct Slice: Identifiable {
        let id: String
        let bytes: UInt64
        let tint: Color
    }

    private func slices(_ memory: SystemMemoryUsage) -> [Slice] {
        [
            Slice(id: "App memory", bytes: memory.app, tint: Theme.Colors.progress),
            Slice(id: "Wired", bytes: memory.wired, tint: Theme.Colors.warning),
            Slice(id: "Compressed", bytes: memory.compressed, tint: Theme.Colors.success),
            Slice(id: "Cached files", bytes: memory.cached, tint: Theme.Colors.textTertiary),
        ]
    }

    private func breakdown(_ memory: SystemMemoryUsage) -> some View {
        let total = Double(max(memory.total, 1))
        let parts = slices(memory)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SystemMeterBar(
                segments: parts.map {
                    SystemMeterBar.Segment(id: $0.id, fraction: Double($0.bytes) / total, tint: $0.tint)
                })
            ForEach(parts) { slice in
                SystemValueRow(title: slice.id, value: SystemFormat.bytes(slice.bytes), tint: slice.tint)
            }
            SystemValueRow(
                title: "Free", value: SystemFormat.bytes(memory.free),
                tint: Theme.Colors.controlSurface)
        }
    }

    private func facts(_ memory: SystemMemoryUsage) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            SystemValueRow(
                title: "Memory pressure", value: memory.pressure.title,
                tint: SystemTint.pressure(memory.pressure))
            SystemValueRow(
                title: "Swap used",
                value: memory.swapTotal == 0
                    ? "None"
                    : "\(SystemFormat.bytes(memory.swapUsed)) of \(SystemFormat.bytes(memory.swapTotal))")
        }
    }
}
