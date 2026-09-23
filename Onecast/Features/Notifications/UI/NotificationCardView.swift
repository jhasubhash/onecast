import SwiftUI

/// The built-in body for a posted notification; a caller can host its own view in its place.
struct NotificationCardView: View {
    let spec: NotificationSpec
    let onAction: (String) -> Void
    let onDismiss: () -> Void

    /// A row-sized well so the glyph and title read at the same weight a menu row gives them.
    private static let iconTile: CGFloat = 34
    private static let iconGlyph: CGFloat = 15

    var body: some View {
        switch spec.style {
        case .toast: toast
        case .banner: banner
        case .card: card
        }
    }

    private var toast: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(spec.title)
                .font(Theme.Typography.bar)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            NotificationCloseButton(action: onDismiss)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .fixedSize()
        .notificationSurface(in: Capsule())
    }

    private var banner: some View {
        HStack(spacing: Theme.Spacing.lg) {
            icon
            textBlock
            Spacer(minLength: Theme.Spacing.md)
            NotificationCloseButton(action: onDismiss)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: Theme.Size.hudMaxWidth, alignment: .leading)
        .notificationSurface(in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.lg) {
                icon
                textBlock
                Spacer(minLength: Theme.Spacing.md)
                NotificationCloseButton(action: onDismiss)
            }
            if !spec.actions.isEmpty {
                HStack(spacing: Theme.Spacing.md) {
                    Spacer(minLength: 0)
                    ForEach(spec.actions) { action in
                        NotificationActionButton(
                            action: action, onActivate: { onAction(action.id) })
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: Theme.Size.dialogWidth, alignment: .leading)
        .notificationSurface(in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// A quiet glyph well: the anchor a bare dark box was missing, so the card reads as a notification.
    private var icon: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.Colors.controlSurface)
            .overlay(
                Image(systemName: "bell.fill")
                    .font(.system(size: Self.iconGlyph, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary.opacity(0.85)))
            .frame(width: Self.iconTile, height: Self.iconTile)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(spec.title)
                .font(Theme.Typography.panelTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
            // An empty body once drew a phantom line that padded every title-only card.
            if !spec.body.isEmpty {
                Text(spec.body)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Reveals its fill on hover, so a sticky card rests clean but the target is unmistakable up close.
private struct NotificationCloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    private static let hit: CGFloat = 18
    private static let glyph: CGFloat = 9

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: Self.glyph, weight: .bold))
                .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                .frame(width: Self.hit, height: Self.hit)
                .background(Circle().fill(hovered ? Theme.Colors.menuHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct NotificationActionButton: View {
    let action: NotificationAction
    let onActivate: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onActivate) {
            Text(action.title)
                .font(Theme.Typography.bar)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.menuButton)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Capsule())
    }
}

extension View {
    /// The shared notification plate: frosted glass over a scrim, with a hairline to lift its edge
    /// off the desktop — a bare `panelScrim` read as a flat black rectangle over a light wallpaper.
    fileprivate func notificationSurface(in shape: some InsettableShape) -> some View {
        background(Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: Theme.Size.hairline))
    }
}
