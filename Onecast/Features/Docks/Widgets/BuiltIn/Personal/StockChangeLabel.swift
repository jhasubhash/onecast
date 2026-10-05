import SwiftUI

extension StockDirection {
    /// Gain and loss take the semantic accents; a flat quote stays in the neutral ink.
    var tint: Color {
        switch self {
        case .up: Theme.Colors.success
        case .down: Theme.Colors.destructive
        case .flat: Theme.Colors.textSecondary
        }
    }

    /// A glyph beside the sign, so a change never relies on colour alone.
    var glyph: String {
        switch self {
        case .up: "arrowtriangle.up.fill"
        case .down: "arrowtriangle.down.fill"
        case .flat: "minus"
        }
    }
}

/// A move as `▲ +0.07%`: tinted, signed and with an arrow.
struct StockChangeLabel: View {
    let direction: StockDirection
    let text: String
    let font: Font
    let glyphSize: CGFloat

    var body: some View {
        HStack(spacing: glyphSize / 3) {
            SymbolImage(name: direction.glyph, size: glyphSize)
            Text(text)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(direction.tint)
        .accessibilityHidden(true)
    }
}
