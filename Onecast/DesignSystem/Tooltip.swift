import SwiftUI

/// Draws hover labels outside the view's own window, for a host whose window would clip them.
struct TooltipPresenter {
    /// `frame` is the control's, in the hosting view's top-left space; `owner` names the control.
    var show: @MainActor (_ owner: UUID, _ text: String, _ frame: CGRect) -> Void
    var hide: @MainActor (_ owner: UUID) -> Void
}

extension EnvironmentValues {
    @Entry var tooltipPresenter: TooltipPresenter?
}

/// A hover label in Onecast's own vocabulary, replacing a system `.help()` tooltip.
private struct TooltipModifier: ViewModifier {
    let text: String?
    let edge: VerticalEdge
    @State private var hovered = false
    @State private var owner = UUID()
    @State private var frame = CGRect.zero
    @Environment(\.metrics) private var metrics
    @Environment(\.tooltipPresenter) private var presenter

    func body(content: Content) -> some View {
        if let presenter {
            hosted(content, by: presenter)
        } else {
            inline(content)
        }
    }

    private func inline(_ content: Content) -> some View {
        content
            .onHover { hovered = text != nil && $0 }
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if let text, hovered {
                    TooltipChip(text: text)
                        // A zero-height frame on the control's edge, so a label of any height hangs off it.
                        .frame(height: 0, alignment: edge == .top ? .bottom : .top)
                        .offset(y: edge == .top ? -metrics.spacing.sm : metrics.spacing.sm)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: Theme.Duration.tooltip), value: hovered)
    }

    /// Re-shown as the frame moves, so a label follows a control the host is animating.
    private func hosted(_ content: Content, by presenter: TooltipPresenter) -> some View {
        content
            .onHover { hovered = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onChange(of: hovered ? text : nil) { _, shown in present(shown, by: presenter) }
            .onChange(of: frame) { if hovered { present(text, by: presenter) } }
            .onDisappear { presenter.hide(owner) }
    }

    private func present(_ text: String?, by presenter: TooltipPresenter) {
        if let text { presenter.show(owner, text, frame) } else { presenter.hide(owner) }
    }
}

extension View {
    /// Hover label styled like the palette's keycap chips; hang it `.bottom` at a window's top.
    func tooltip(_ text: String?, edge: VerticalEdge = .top) -> some View {
        modifier(TooltipModifier(text: text, edge: edge))
    }
}

/// The label itself, keycap-styled; a host drawing it in its own window backs it as it sees fit.
struct TooltipChip: View {
    let text: String
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text(text)
            .font(metrics.typography.keyCap)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.xxs)
            .background(Capsule().fill(Theme.Colors.controlSurface))
            .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
            .fixedSize()
    }
}
