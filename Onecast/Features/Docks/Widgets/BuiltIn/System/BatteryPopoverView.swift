import OnecastPluginKit
import SwiftUI

struct BatteryPopoverView: View {
    let context: DockWidgetContext
    private let monitor = DockWidgetServices.current.battery

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if let reading = monitor.reading {
                header(symbol: reading.symbol, title: "\(reading.percent)%", subtitle: reading.statusTitle)
                powerRows(reading)
                healthSection
                lowPowerRow
            } else {
                header(symbol: "powerplug.fill", title: "AC Power", subtitle: "This Mac has no battery.")
            }
            settingsButton
        }
        .padding(SystemPopover.padding)
        .frame(width: SystemPopover.width, alignment: .leading)
    }

    private func header(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.xl) {
            SymbolImage(name: symbol, size: Theme.Size.dialogIcon)
                .foregroundStyle(Theme.Colors.textPrimary)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.calcResult)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func powerRows(_ reading: SystemBatteryReading) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            SystemValueRow(
                title: "Power source", value: reading.isOnAdapter ? "Power adapter" : "Battery")
            if let estimate = reading.estimateText {
                SystemValueRow(
                    title: reading.status == .charging ? "Until full" : "Remaining", value: estimate)
            }
            if let watts = monitor.details.adapterWatts, reading.isOnAdapter {
                SystemValueRow(title: "Adapter", value: "\(watts) W")
            }
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        let details = monitor.details
        if !details.isEmpty, details.healthPercent != nil || details.cycleCount != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SystemSectionHeader(title: "Battery Health")
                if let health = details.healthPercent {
                    SystemValueRow(title: "Maximum capacity", value: "\(health)%")
                }
                if let cycles = details.cycleCount {
                    SystemValueRow(title: "Cycle count", value: "\(cycles)")
                }
                if let temperature = details.temperatureCelsius {
                    SystemValueRow(title: "Temperature", value: String(format: "%.1f °C", temperature))
                }
                if let voltage = details.voltage {
                    SystemValueRow(title: "Voltage", value: String(format: "%.2f V", voltage))
                }
            }
        }
    }

    private var lowPowerRow: some View {
        SystemValueRow(title: "Low Power Mode", value: monitor.isLowPowerMode ? "On" : "Off")
    }

    @ViewBuilder
    private var settingsButton: some View {
        if let url = Self.settingsURL {
            BarButton(chrome: .rounded, action: { context.actions.openURL(url) }) {
                Text("Battery Settings…")
                    .font(Theme.Typography.bar)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }
}
