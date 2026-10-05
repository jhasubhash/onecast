import AppKit
import SwiftUI

/// The cover as a play/pause button, for a tile with no room for a control of its own.
struct NowPlayingArtworkToggle: View {
    let image: NSImage?
    let side: CGFloat
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovered = false

    private static let glyphFraction: CGFloat = 0.4
    private static let cornerFraction: CGFloat = 0.2

    var body: some View {
        Button(action: action) {
            ZStack {
                NowPlayingArtworkView(image: image, side: side)
                if hovered {
                    RoundedRectangle(cornerRadius: side * Self.cornerFraction, style: .continuous)
                        .fill(Theme.Colors.panelScrim)
                    SymbolImage(name: isPlaying ? "pause.fill" : "play.fill", size: side * Self.glyphFraction)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .tooltip(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}
