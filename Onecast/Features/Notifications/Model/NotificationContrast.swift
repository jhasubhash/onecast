import Foundation

/// Which ink reads on a coloured card: light or dark text, icon and controls.
enum NotificationInk: Equatable, Sendable {
    case light
    case dark
}

/// WCAG contrast from a background's linear sRGB components, so text on a tinted card stays legible
/// whatever the colour and whichever appearance resolved it.
enum NotificationContrast {
    /// WCAG's floor for bold text and UI glyphs. White wins whenever it clears it, as on the system's
    /// own blue and red buttons; a strict "higher ratio" pick put black text on blue.
    static let lightInkMinimum = 3.0

    static func ink(linearRed red: Double, green: Double, blue: Double) -> NotificationInk {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return 1.05 / (luminance + 0.05) >= lightInkMinimum ? .light : .dark
    }
}
