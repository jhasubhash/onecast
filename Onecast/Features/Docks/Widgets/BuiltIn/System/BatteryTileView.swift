import OnecastPluginKit
import SwiftUI

struct BatteryTileView: View {
    let context: DockWidgetContext
    private let monitor = DockWidgetServices.current.battery
    @State private var lease: SystemSamplerLease?

    var body: some View {
        let metrics = SystemTileMetrics(context)
        SystemTileFrame(metrics) { content(metrics) }
            .onAppear { if lease == nil { lease = monitor.lease() } }
            .onDisappear { lease = nil }
    }

    @ViewBuilder
    private func content(_ metrics: SystemTileMetrics) -> some View {
        if !monitor.hasRead {
            Color.clear
        } else if let reading = monitor.reading {
            batteryView(reading, metrics)
        } else {
            SystemMetricReadout(
                label: "Power", tint: Theme.Colors.success, value: "AC Power",
                caption: metrics.isCompact ? nil : "No battery",
                labelPosition: metrics.isCompact ? .below : .above, metrics: metrics)
        }
    }

    private func batteryView(_ reading: SystemBatteryReading, _ metrics: SystemTileMetrics) -> some View {
        let layout = metrics.isVertical
            ? AnyLayout(VStackLayout(spacing: metrics.spacing * 2))
            : AnyLayout(HStackLayout(spacing: metrics.spacing * 2))
        return layout {
            SystemMetricReadout(
                label: metrics.isCompact ? reading.tileTitle : "Battery", tint: tint(reading),
                value: "\(reading.percent)%", caption: metrics.isCompact ? nil : caption(reading),
                labelPosition: metrics.isCompact ? .below : .above, metrics: metrics)
            if !metrics.isCompact {
                SystemMeterBar(
                    fraction: Double(reading.percent) / 100, tint: tint(reading),
                    height: metrics.tileLength * 0.1
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(accessibilityValue(reading))
    }

    private func caption(_ reading: SystemBatteryReading) -> String {
        reading.timeText ?? reading.tileTitle
    }

    private func tint(_ reading: SystemBatteryReading) -> Color {
        if reading.isLow { return Theme.Colors.destructive }
        return reading.isOnAdapter ? Theme.Colors.success : Theme.Colors.progress
    }

    private func accessibilityValue(_ reading: SystemBatteryReading) -> String {
        ["\(reading.percent) percent", reading.statusTitle, reading.timeText]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
