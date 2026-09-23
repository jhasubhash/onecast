import SwiftUI

/// The built-in body for a posted notification; a caller can host its own view in its place.
struct NotificationCardView: View {
    let spec: NotificationSpec
    let onAction: (String) -> Void
    let onDismiss: () -> Void
    @Environment(\.self) private var environment

    private var palette: NotificationPalette { NotificationPalette(tint: spec.tint, in: environment) }
    /// A row-sized well so the glyph and title read at the same weight a menu row gives them.
    private static let iconTile: CGFloat = 34
    private static let iconGlyph: CGFloat = 15

    var body: some View {
        let palette = palette
        switch spec.style {
        case .toast: toast(palette)
        case .banner: banner(palette)
        case .card: card(palette)
        }
    }

    private func toast(_ palette: NotificationPalette) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(spec.title)
                .font(Theme.Typography.bar)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            NotificationCloseButton(palette: palette, action: onDismiss)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .fixedSize()
        .notificationSurface(in: Capsule(), palette: palette)
    }

    private func banner(_ palette: NotificationPalette) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            icon(palette)
            textBlock(palette)
            Spacer(minLength: Theme.Spacing.md)
            NotificationCloseButton(palette: palette, action: onDismiss)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: Theme.Size.hudMaxWidth, alignment: .leading)
        .notificationSurface(
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous), palette: palette)
    }

    private func card(_ palette: NotificationPalette) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.lg) {
                icon(palette)
                textBlock(palette)
                Spacer(minLength: Theme.Spacing.md)
                NotificationCloseButton(palette: palette, action: onDismiss)
            }
            if !spec.actions.isEmpty {
                HStack(spacing: Theme.Spacing.md) {
                    Spacer(minLength: 0)
                    ForEach(spec.actions) { action in
                        NotificationActionButton(
                            action: action, palette: palette, onActivate: { onAction(action.id) })
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: Theme.Size.dialogWidth, alignment: .leading)
        .notificationSurface(
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous), palette: palette)
    }

    /// A quiet glyph well: the anchor a bare dark box was missing, so the card reads as a notification.
    private func icon(_ palette: NotificationPalette) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(palette.well)
            .overlay(
                Image(systemName: "bell.fill")
                    .font(.system(size: Self.iconGlyph, weight: .semibold))
                    .foregroundStyle(palette.glyph))
            .frame(width: Self.iconTile, height: Self.iconTile)
    }

    private func textBlock(_ palette: NotificationPalette) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(spec.title)
                .font(Theme.Typography.panelTitle)
                .foregroundStyle(palette.primary)
                .lineLimit(2)
            // An empty body once drew a phantom line that padded every title-only card.
            if !spec.body.isEmpty {
                Text(spec.body)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Reveals its fill on hover, so a sticky card rests clean but the target is unmistakable up close.
private struct NotificationCloseButton: View {
    let palette: NotificationPalette
    let action: () -> Void
    @State private var hovered = false

    private static let hit: CGFloat = 18
    private static let glyph: CGFloat = 9

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: Self.glyph, weight: .bold))
                .foregroundStyle(hovered ? palette.primary : palette.tertiary)
                .frame(width: Self.hit, height: Self.hit)
                .background(Circle().fill(hovered ? palette.hover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct NotificationActionButton: View {
    let action: NotificationAction
    let palette: NotificationPalette
    let onActivate: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onActivate) {
            Text(action.title)
                .font(Theme.Typography.bar)
                .foregroundStyle(palette.primary)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.menuButton)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? palette.hover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Capsule())
    }
}

extension View {
    /// The shared notification plate: frosted glass over a scrim, with a hairline to lift its edge
    /// off the desktop. A tint paints over both, so the chosen colour is the card's own background.
    fileprivate func notificationSurface(
        in shape: some InsettableShape, palette: NotificationPalette
    ) -> some View {
        background(palette.fill ?? Color.clear)
            .background(Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .clipShape(shape)
            .overlay(shape.strokeBorder(palette.stroke, lineWidth: Theme.Size.hairline))
    }
}
