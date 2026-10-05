import OnecastPluginKit
import SwiftUI

/// Why a quote could not be got, with the way to put it right: Try again, or the settings.
struct StockFailureView: View {
    let error: StockError
    let context: DockWidgetContext
    let retry: () -> Void

    private static let glyph: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                SymbolImage(name: "exclamationmark.triangle", size: Self.glyph)
                    .foregroundStyle(Theme.Colors.warning)
                Text(error.message)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if error.isTransient {
                button("Try again", action: retry)
            } else {
                button("Open Settings") { context.actions.openSettings() }
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
        .accessibilityLabel(title)
    }
}
