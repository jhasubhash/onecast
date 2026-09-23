import SwiftUI

/// The UI layer's mapping from the Foundation-only `NotificationTint`; the card, the scheduler's
/// swatches and their labels all read it, so a tint looks the same wherever it is picked or shown.
extension NotificationTint {
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .gray: return .gray
        }
    }

    var title: String { rawValue.capitalized }
}

/// Every colour a card draws, derived once from its tint: nil keeps the neutral glass card.
struct NotificationPalette {
    let fill: Color?
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let well: Color
    let glyph: Color
    let hover: Color
    let stroke: Color

    static let neutral = NotificationPalette(
        fill: nil, primary: Theme.Colors.textPrimary, secondary: Theme.Colors.textSecondary,
        tertiary: Theme.Colors.textTertiary, well: Theme.Colors.controlSurface,
        glyph: Theme.Colors.textPrimary.opacity(0.85), hover: Theme.Colors.menuHover,
        stroke: Theme.Colors.cardStroke)
}

extension NotificationPalette {
    /// The ink is chosen against the tint as this appearance resolves it, not a fixed guess per colour.
    init(tint: NotificationTint?, in environment: EnvironmentValues) {
        guard let tint else {
            self = .neutral
            return
        }
        let resolved = tint.color.resolve(in: environment)
        let contrast = NotificationContrast.ink(
            linearRed: Double(resolved.linearRed), green: Double(resolved.linearGreen),
            blue: Double(resolved.linearBlue))
        let ink: Color = contrast == .light ? .white : .black
        self.init(
            fill: tint.color, primary: ink, secondary: ink.opacity(0.78), tertiary: ink.opacity(0.6),
            well: ink.opacity(0.16), glyph: ink, hover: ink.opacity(0.14), stroke: ink.opacity(0.2))
    }
}
