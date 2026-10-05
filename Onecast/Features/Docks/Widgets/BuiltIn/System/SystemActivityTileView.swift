import OnecastPluginKit
import SwiftUI

struct SystemActivityTileView: View {
    let context: DockWidgetContext
    private let sampler = DockWidgetServices.current.activity
    @State private var lease: SystemSamplerLease?
    @AppStorage private var metricName: String

    init(context: DockWidgetContext) {
        self.context = context
        _metricName = AppStorage(
            wrappedValue: SystemActivityMetric.cpu.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: SystemActivityWidget.PreferenceName.metric))
    }

    private var lead: SystemActivityMetric {
        SystemActivityMetric(rawValue: metricName) ?? .cpu
    }

    /// The second figure a compact tile stacks under the lead one.
    private var partner: SystemActivityMetric {
        lead == .cpu ? .memory : .cpu
    }

    var body: some View {
        let metrics = SystemTileMetrics(context)
        SystemTileFrame(metrics) {
            switch context.size {
            case .compact:
                VStack(spacing: metrics.spacing * 2) {
                    readout(lead, metrics)
                    readout(partner, metrics)
                }
            case .wide:
                axis(metrics) {
                    readout(lead, metrics, caption: caption(lead), above: true)
                    chart(lead, metrics)
                }
            case .expanded:
                axis(metrics) {
                    readout(.cpu, metrics)
                    readout(.memory, metrics)
                    readout(.storage, metrics)
                    chart(lead, metrics)
                }
            }
        }
        .onAppear { if lease == nil { lease = sampler.lease() } }
        .onDisappear { lease = nil }
    }

    private func axis<Content: View>(
        _ metrics: SystemTileMetrics, @ViewBuilder content: () -> Content
    ) -> some View {
        let layout = metrics.isVertical
            ? AnyLayout(VStackLayout(spacing: metrics.spacing * 2))
            : AnyLayout(HStackLayout(spacing: metrics.spacing * 2))
        return layout { content() }
    }

    private var rootVolume: SystemStorage.Volume? {
        sampler.volumes.first { $0.isRoot } ?? sampler.volumes.first
    }

    private func fraction(_ metric: SystemActivityMetric) -> Double? {
        switch metric {
        case .cpu: sampler.cpu?.overall
        case .memory: sampler.memory?.usedFraction
        case .storage: rootVolume?.usedFraction
        }
    }

    /// The dot beside each label, one fixed hue per metric.
    private func accent(_ metric: SystemActivityMetric) -> Color {
        switch metric {
        case .cpu: Theme.Colors.brand
        case .memory: Theme.Colors.progress
        case .storage: Theme.Colors.warning
        }
    }

    /// The chart's hue, which warns as the figure climbs.
    private func chartTint(_ metric: SystemActivityMetric) -> Color {
        let value = fraction(metric) ?? 0
        guard metric == .memory, let memory = sampler.memory else { return SystemTint.load(value) }
        return SystemTint.pressure(memory.pressure)
    }

    private func readout(
        _ metric: SystemActivityMetric, _ metrics: SystemTileMetrics, caption: String? = nil,
        above: Bool = false
    ) -> some View {
        SystemMetricReadout(
            label: above ? metric.title : metric.shortTitle, tint: accent(metric),
            value: fraction(metric).map(SystemFormat.percent) ?? "–", caption: caption,
            labelPosition: above ? .above : .below, metrics: metrics)
    }

    @ViewBuilder
    private func chart(_ metric: SystemActivityMetric, _ metrics: SystemTileMetrics) -> some View {
        Group {
            switch metric {
            case .cpu:
                SystemSparkline(
                    series: sampler.cpuHistory, ceiling: 1, tint: chartTint(.cpu),
                    lineWidth: metrics.tileLength * 0.03)
            case .memory:
                SystemSparkline(
                    series: sampler.memoryHistory, ceiling: 1, tint: chartTint(.memory),
                    lineWidth: metrics.tileLength * 0.03)
            case .storage:
                SystemMeterBar(fraction: fraction(.storage) ?? 0, tint: chartTint(.storage))
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func caption(_ metric: SystemActivityMetric) -> String? {
        switch metric {
        case .cpu:
            sampler.loadAverages.first.map { String(format: "Load %.1f", $0) }
        case .memory:
            sampler.memory.map { "\(SystemFormat.bytes($0.used)) used" }
        case .storage:
            rootVolume.map { "\(SystemFormat.bytes($0.available)) free" }
        }
    }
}
