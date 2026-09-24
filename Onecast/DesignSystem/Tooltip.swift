import SwiftUI

/// A hover label in Onecast's own vocabulary, replacing a system `.help()` tooltip.
private struct TooltipModifier: ViewModifier {
    let text: String?
    let edge: VerticalEdge
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content
            .onHover { hovered = text != nil && $0 }
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if let text, hovered {
                    Text(text)
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, metrics.spacing.sm)
                        .padding(.vertical, metrics.spacing.xxs)
                        .background(Capsule().fill(Theme.Colors.controlSurface))
                        .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
                        .fixedSize()
                        // A zero-height frame on the control's edge, so a label of any height hangs off it.
                        .frame(height: 0, alignment: edge == .top ? .bottom : .top)
                        .offset(y: edge == .top ? -metrics.spacing.sm : metrics.spacing.sm)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: Theme.Duration.tooltip), value: hovered)
    }
}

extension View {
    /// Hover label styled like the palette's keycap chips; hang it `.bottom` at a window's top.
    func tooltip(_ text: String?, edge: VerticalEdge = .top) -> some View {
        modifier(TooltipModifier(text: text, edge: edge))
    }
}
