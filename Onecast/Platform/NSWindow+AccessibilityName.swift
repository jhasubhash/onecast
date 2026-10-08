import AppKit

extension NSWindow {
    /// An untitled panel reads as blank to AX, so a driver can't tell the palette from a HUD.
    func nameForAccessibility(_ identifier: String, title: String) {
        setAccessibilityIdentifier("onecast." + identifier)
        setAccessibilityTitle(title)
    }
}
