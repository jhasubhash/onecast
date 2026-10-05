import SwiftUI

/// A popover button: a capsule that lifts on hover, or fills with the accent as the main action.
struct TimeActionButton: View {
    private static let disabledOpacity: CGFloat = 0.4
    private static let hoveredProminentOpacity: CGFloat = 0.85

    let title: String
    var symbol: String?
    var isProminent = false
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let symbol {
                    SymbolImage(name: symbol, size: Theme.Typography.menuSymbolSize)
                }
                Text(title)
                    .font(Theme.Typography.bar)
                    .lineLimit(1)
            }
            .foregroundStyle(isProminent ? Color.white : Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.barButtonHeight)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .opacity(isEnabled ? 1 : Self.disabledOpacity)
    }

    private var fill: AnyShapeStyle {
        if isProminent {
            return AnyShapeStyle(Theme.Colors.progress.opacity(hovered ? Self.hoveredProminentOpacity : 1))
        }
        return AnyShapeStyle(hovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface)
    }
}
