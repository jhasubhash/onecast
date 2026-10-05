import SwiftUI

/// One labelled figure in a popover: the name quiet on the left, the value on the right.
struct SystemValueRow: View {
    let title: String
    let value: String
    var tint: Color?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let tint {
                Circle().fill(tint).frame(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
            }
            Text(title)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: Theme.Spacing.md)
            Text(value)
                .font(Theme.Typography.rowTrailing.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
