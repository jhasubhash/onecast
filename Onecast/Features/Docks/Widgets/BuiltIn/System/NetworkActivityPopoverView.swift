import OnecastPluginKit
import SwiftUI

struct NetworkActivityPopoverView: View {
    let context: DockWidgetContext
    private let sampler = DockWidgetServices.current.network
    @AppStorage private var scopeName: String

    private static let graphHeight: CGFloat = 56
    private static let lineWidth: CGFloat = 2
    private static let interfaceLimit = 6
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
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            header
            graph
            totals
            wifiSection
            interfaceSection
        }
        .padding(SystemPopover.padding)
        .frame(width: SystemPopover.width, alignment: .leading)
    }

    private var header: some View {
        let rate = sampler.sample.throughput(for: scope)
        return HStack(spacing: Theme.Spacing.xxl) {
            bigReadout("arrow.down", SystemTint.download, rate.download, "Download")
            bigReadout("arrow.up", SystemTint.upload, rate.upload, "Upload")
            Spacer(minLength: 0)
        }
    }

    private func bigReadout(
        _ symbol: String, _ tint: Color, _ rate: Double, _ title: String
    ) -> some View {
        let quantity = SystemFormat.byteQuantity(rate)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                SymbolImage(name: symbol, size: Theme.Typography.menuSymbolSize).foregroundStyle(tint)
                Text(quantity.value)
                    .font(Theme.Typography.calcResult.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(quantity.unit)/s")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text(title)
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(SystemFormat.rate(rate))
    }

    private var graph: some View {
        let history = sampler.history(for: scope)
        let ceiling = SystemSeries.niceCeiling(
            for: max(history.download.peak, history.upload.peak), floor: Self.ceilingFloor)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ZStack {
                SystemSparkline(
                    series: history.download, ceiling: ceiling, tint: SystemTint.download,
                    lineWidth: Self.lineWidth)
                SystemSparkline(
                    series: history.upload, ceiling: ceiling, tint: SystemTint.upload,
                    lineWidth: Self.lineWidth)
            }
            .frame(height: Self.graphHeight)
            Text("Last minute · scale up to \(SystemFormat.rate(ceiling))")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var totals: some View {
        let traffic = sampler.sample.totalTraffic
        return VStack(spacing: Theme.Spacing.sm) {
            SystemValueRow(title: "Downloaded since started", value: SystemFormat.bytes(traffic.received))
            SystemValueRow(title: "Uploaded since started", value: SystemFormat.bytes(traffic.sent))
        }
    }

    @ViewBuilder
    private var wifiSection: some View {
        if let wifi = sampler.wifi, wifi.ssid != nil || wifi.signal != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SystemSectionHeader(title: "Wi-Fi")
                if let ssid = wifi.ssid {
                    SystemValueRow(title: "Network", value: ssid)
                }
                if let signal = wifi.signal {
                    SystemValueRow(title: "Signal", value: "\(signal) dBm")
                }
                if let rate = wifi.transmitRate {
                    SystemValueRow(title: "Link speed", value: String(format: "%.0f Mbps", rate))
                }
            }
        }
    }

    @ViewBuilder
    private var interfaceSection: some View {
        let interfaces = sampler.sample.visibleInterfaces
        if !interfaces.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SystemSectionHeader(title: "Interfaces")
                ForEach(interfaces.prefix(Self.interfaceLimit)) { interface in
                    interfaceRow(interface)
                }
                if interfaces.count > Self.interfaceLimit {
                    Text("and \(interfaces.count - Self.interfaceLimit) more")
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private func interfaceRow(_ interface: SystemNetworkSample.Interface) -> some View {
        let isPrimary = interface.name == sampler.sample.primary?.name
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(isPrimary ? "\(interface.name) · primary" : interface.name)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text([interface.kind.title, interface.address].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.md)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text("↓ \(SystemFormat.rate(interface.throughput.download))")
                Text("↑ \(SystemFormat.rate(interface.throughput.upload))")
            }
            .font(Theme.Typography.keyCap.monospacedDigit())
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
