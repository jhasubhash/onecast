import OnecastPluginKit
import SwiftUI

/// Why the weather could not be got, with the ways to put it right.
struct WeatherPopoverFailure: View {
    let failure: PersonalWeatherFailure
    let isRefreshing: Bool
    let context: DockWidgetContext
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                SymbolImage(name: "exclamationmark.triangle", size: Self.glyph)
                    .foregroundStyle(Theme.Colors.warning)
                Text(failure.message)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Spacing.sm) {
                if failure.offersRetry {
                    button("Try again", action: retry)
                        .disabled(isRefreshing)
                }
                if let remedy = failure.remedy {
                    button("Open Settings") { open(remedy) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        BarButton(chrome: .rounded, action: action) {
            Text(title)
                .font(Theme.Typography.bar)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .accessibilityLabel(title)
    }

    private func open(_ remedy: PersonalWeatherFailure.Remedy) {
        switch remedy {
        case .widgetSettings: context.actions.openSettings()
        case .locationPrivacy: context.actions.openURL(Self.locationPrivacyURL)
        }
    }

    private static let glyph: CGFloat = 14
    private static let locationPrivacyURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
}
