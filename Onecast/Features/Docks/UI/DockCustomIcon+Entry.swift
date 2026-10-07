import AppKit
import SwiftUI

extension DockCustomIcon {
    /// What `EntryIconView` and `IconCache` draw for it.
    var entryIcon: EntryIcon {
        switch self {
        case .image(let path):
            .artwork(path: path, extent: IconCache.appIconExtent, stamp: Self.stamp(ofFileAt: path))
        case .symbol(let name, let color):
            if let color { .tintedSymbol(name: name, tint: color.entryTint) } else { .symbol(name) }
        }
    }

    /// Moves when the image file is edited, so the cache never serves the picture it replaced.
    private static func stamp(ofFileAt path: String) -> Int {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return Int(modified?.timeIntervalSince1970 ?? 0)
    }
}

/// A symbol on a card that fills its tile, as a widget's card does: an app icon is drawn smaller
/// than its tile (its own artwork carries the margin), which beside a widget reads as undersized.
struct DockSymbolCard: View {
    let name: String
    let color: DockColor?
    let side: CGFloat

    /// The glyph's share of the tile's side.
    private static let glyphRatio: CGFloat = 0.5

    var body: some View {
        RoundedRectangle(cornerRadius: DockPlateShape.cardRadius(tileSize: side), style: .continuous)
            .fill(color?.swatch ?? Theme.Colors.controlSurface)
            .frame(width: side, height: side)
            .overlay {
                SymbolImage(name: name, size: side * Self.glyphRatio)
                    .foregroundStyle(color == nil ? Color.primary.opacity(0.85) : Color.white)
            }
            .accessibilityHidden(true)
    }
}
