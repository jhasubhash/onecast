import SwiftUI

/// A focusable control-surface button — a Tab stop that opens its popover on ↩︎/Space or a click,
/// drawing our own focused edge instead of AppKit's ring. Generic over the form's field enum so
/// every in-palette editor navigates its controls the same way.
struct FormControlButton<Field: Hashable, Label: View>: View {
    let width: CGFloat
    let field: Field
    var focus: FocusState<Field?>.Binding
    let action: () -> Void
    @ViewBuilder let label: Label
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) { label }
            .font(.body)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(width: width, height: Theme.Size.barButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
            .contentShape(Rectangle())
            .focusable()
            .focused(focus, equals: field)
            .formFocusRing(focus.wrappedValue == field, radius: metrics.radius.menu)
            .onTapGesture { activate() }
            .onKeyPress(.space) { activate(); return .handled }
            .onKeyPress(.return) { activate(); return .handled }
    }

    private func activate() {
        focus.wrappedValue = field
        action()
    }
}

/// A focusable checkbox row — a Tab stop that flips on ↩︎/Space or a click, drawn ourselves so it
/// takes a focused edge instead of AppKit's ring.
struct FormCheckbox<Field: Hashable>: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let field: Field
    var focus: FocusState<Field?>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.body)
                .foregroundStyle(isOn ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.xs)
        .contentShape(Rectangle())
        .focusable()
        .focused(focus, equals: field)
        .formFocusRing(focus.wrappedValue == field, radius: Theme.Radius.row)
        .onTapGesture { toggle() }
        .onKeyPress(.space) { toggle(); return .handled }
        .onKeyPress(.return) { toggle(); return .handled }
    }

    private func toggle() {
        focus.wrappedValue = field
        isOn.toggle()
    }
}
