import AppKit

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
