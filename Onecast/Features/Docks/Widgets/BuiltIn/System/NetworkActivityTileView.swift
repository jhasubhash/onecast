import OnecastPluginKit
import SwiftUI

struct NetworkActivityTileView: View {
    let context: DockWidgetContext
    private let sampler = DockWidgetServices.current.network
    @State private var lease: SystemSamplerLease?
    @AppStorage private var scopeName: String

    /// A graph never rescales below this, so an idle link stays a flat line, not a noisy one.
    private static let ceilingFloor = 10_000.0

    init(context: DockWidgetContext) {
        self.context = context
        _scopeName = AppStorage(
            wrappedValue: SystemNetworkSample.Scope.primary.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: NetworkActivityWidget.PreferenceName.scope))
    }

    private var scope: SystemNetworkSample.Scope {
        SystemNetworkSample.Scope(rawValue: scopeName) ?? .primary
    }

    var body: some View {
        let metrics = SystemTileMetrics(context)
        SystemTileFrame(metrics) {
            switch context.size {
            case .compact: readouts(metrics)
            case .wide, .expanded: graphLayout(metrics)
            }
        }
        .onAppear { if lease == nil { lease = sampler.lease() } }
        .onDisappear { lease = nil }
    }

    private func readouts(_ metrics: SystemTileMetrics) -> some View {
        let rate = sampler.sample.throughput(for: scope)
        return VStack(spacing: metrics.spacing * 2) {
            readout("Down", Theme.Colors.progress, rate.download, metrics)
            readout("Up", Theme.Colors.success, rate.upload, metrics)
        }
    }

    private func readout(
        _ label: String, _ tint: Color, _ rate: Double, _ metrics: SystemTileMetrics
    ) -> some View {
        let quantity = SystemFormat.byteQuantity(rate)
        return SystemMetricReadout(
            label: label, tint: tint, value: "\(quantity.value) \(quantity.unit)", caption: nil,
            metrics: metrics)
    }

    private func graphLayout(_ metrics: SystemTileMetrics) -> some View {
        let layout = metrics.isVertical
            ? AnyLayout(VStackLayout(spacing: metrics.spacing * 2))
            : AnyLayout(HStackLayout(spacing: metrics.spacing * 2))
        let history = sampler.history(for: scope)
        let ceiling = SystemSeries.niceCeiling(
            for: max(history.download.peak, history.upload.peak), floor: Self.ceilingFloor)
        return layout {
            readouts(metrics)
            ZStack {
                SystemSparkline(
                    series: history.download, ceiling: ceiling, tint: Theme.Colors.progress,
                    lineWidth: metrics.tileLength * 0.03)
                SystemSparkline(
                    series: history.upload, ceiling: ceiling, tint: Theme.Colors.success,
                    lineWidth: metrics.tileLength * 0.03)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
