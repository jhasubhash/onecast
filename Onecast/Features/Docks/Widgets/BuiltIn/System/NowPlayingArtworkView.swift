import AppKit
import SwiftUI

/// A track's cover, or a quiet placeholder while there is none.
struct NowPlayingArtworkView: View {
    let image: NSImage?
    let side: CGFloat

    private static let cornerFraction: CGFloat = 0.2
    private static let placeholderGlyphFraction: CGFloat = 0.4

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Theme.Colors.iconPlaceholder)
                SymbolImage(name: "music.note", size: side * Self.placeholderGlyphFraction)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * Self.cornerFraction, style: .continuous))
        .accessibilityHidden(true)
    }
}
