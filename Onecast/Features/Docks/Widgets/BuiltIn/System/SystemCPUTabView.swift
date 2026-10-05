import SwiftUI

struct SystemCPUTabView: View {
    private let sampler = DockWidgetServices.current.activity

    private static let graphHeight: CGFloat = 56
    private static let lineWidth: CGFloat = 2
    private static let coreColumns = 2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                SystemSparkline(
                    series: sampler.cpuHistory, ceiling: 1, tint: tint, lineWidth: Self.lineWidth
                )
                .frame(height: Self.graphHeight)
                facts
                cores
            }
        }
    }

    private var tint: Color { SystemTint.load(sampler.cpu?.overall ?? 0) }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(sampler.cpu.map { SystemFormat.percent($0.overall) } ?? "–")
                .font(Theme.Typography.calcResult.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
            if let cpu = sampler.cpu {
                Text("User \(SystemFormat.percent(cpu.user)) · System \(SystemFormat.percent(cpu.system))")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var facts: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if sampler.loadAverages.count == 3 {
                SystemValueRow(
                    title: "Load average (1, 5, 15 min)",
                    value: sampler.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: " · "))
            }
            SystemValueRow(title: "Thermal state", value: sampler.thermalState.title)
            if sampler.bootDate != nil {
                SystemValueRow(title: "Uptime", value: SystemFormat.uptime(seconds: sampler.uptime))
            }
        }
    }

    @ViewBuilder
    private var cores: some View {
        if let cpu = sampler.cpu, cpu.cores.count > 1 {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SystemSectionHeader(title: "Cores")
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Theme.Spacing.xl), count: Self.coreColumns),
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(Array(cpu.cores.enumerated()), id: \.offset) { index, usage in
                        HStack(spacing: Theme.Spacing.md) {
                            Text("\(index + 1)")
                                .font(Theme.Typography.keyCap.monospacedDigit())
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .frame(minWidth: Theme.Size.keyCap, alignment: .trailing)
                            SystemMeterBar(fraction: usage, tint: SystemTint.load(usage))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Core \(index + 1)")
                        .accessibilityValue(SystemFormat.percent(usage))
                    }
                }
            }
        }
    }
}

private extension ProcessInfo.ThermalState {
    /// What the system's four levels read as to a person.
    var title: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
