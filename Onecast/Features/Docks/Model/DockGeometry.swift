import CoreGraphics
import Foundation

/// Where a dock's window sits and how its tiles size, from screen rects the caller supplies.
enum DockGeometry {
    /// Padding between the tiles and the dock's rim, as a fraction of the tile size.
    static let insetRatio: CGFloat = 0.18
    /// Gap between neighbouring tiles, as a fraction of the tile size.
    static let gapRatio: CGFloat = 0.12
    /// Distance from the screen edge to the dock's rim when shown.
    static let edgeMargin: CGFloat = 6
    /// How much of an auto-hidden dock stays on screen as its handle.
    static let handleThickness: CGFloat = 4

    /// What one slot occupies along the dock's axis, in units of tile size.
    enum Extent: Sendable, Equatable {
        case tile
        case span(Int)
        case spacer(DockSpacerSize)
        case divider

        func length(tileSize: CGFloat) -> CGFloat {
            let gap = tileSize * gapRatio
            switch self {
            case .tile: return tileSize
            case .span(let count): return tileSize * CGFloat(count) + gap * CGFloat(count - 1)
            case .spacer(.small): return tileSize * 0.5
            case .spacer(.regular): return tileSize
            case .divider: return max(1, tileSize * 0.2)
            }
        }
    }

    /// The dock's thickness across its axis: one tile plus its rim.
    static func thickness(tileSize: CGFloat) -> CGFloat {
        tileSize + 2 * tileSize * insetRatio
    }

    /// Total length of a run of slots along the axis, rim included.
    static func length(of extents: [Extent], tileSize: CGFloat) -> CGFloat {
        let tiles = extents.reduce(0) { $0 + $1.length(tileSize: tileSize) }
        let gaps = CGFloat(max(extents.count - 1, 0)) * tileSize * gapRatio
        return tiles + gaps + 2 * tileSize * insetRatio
    }

    /// The shown frame: hugging `edge` of `screen`, centred at `alignment` along it, never off it.
    ///
    /// `screen` is the display's full frame; `available` its visible frame, which already
    /// excludes the menu bar and any edge the macOS Dock reserves.
    static func frame(
        length: CGFloat, thickness: CGFloat, edge: DockEdge, alignment: Double,
        screen: CGRect, available: CGRect
    ) -> CGRect {
        let along = edge.isVertical ? available.height : available.width
        let clampedLength = min(length, along)
        let centre = CGFloat(min(max(alignment, 0), 1))
        switch edge {
        case .bottom:
            let x = clamp(
                available.minX + available.width * centre - clampedLength / 2,
                available.minX, available.maxX - clampedLength)
            return CGRect(
                x: x, y: screen.minY + edgeMargin, width: clampedLength, height: thickness)
        case .left, .right:
            let y = clamp(
                available.maxY - available.height * centre - clampedLength / 2,
                available.minY, available.maxY - clampedLength)
            let x =
                edge == .left
                ? screen.minX + edgeMargin : screen.maxX - edgeMargin - thickness
            return CGRect(x: x, y: y, width: thickness, height: clampedLength)
        }
    }

    /// The auto-hidden frame: slid off its edge, leaving `visible` points showing.
    static func hiddenFrame(shown: CGRect, edge: DockEdge, screen: CGRect, visible: CGFloat)
        -> CGRect
    {
        var frame = shown
        switch edge {
        case .bottom: frame.origin.y = screen.minY - shown.height + visible
        case .left: frame.origin.x = screen.minX - shown.width + visible
        case .right: frame.origin.x = screen.maxX - visible
        }
        return frame
    }

    /// The band along `edge` that reveals an auto-hidden dock when the pointer enters it.
    static func revealZone(shown: CGRect, edge: DockEdge, screen: CGRect, depth: CGFloat = 2)
        -> CGRect
    {
        switch edge {
        case .bottom:
            return CGRect(x: shown.minX, y: screen.minY, width: shown.width, height: depth)
        case .left:
            return CGRect(x: screen.minX, y: shown.minY, width: depth, height: shown.height)
        case .right:
            return CGRect(x: screen.maxX - depth, y: shown.minY, width: depth, height: shown.height)
        }
    }

    /// The macOS Dock-style lens: full `magnified` size under the pointer, falling off over
    /// `reach` tiles either side. `distance` is from the pointer to the tile's centre, in points.
    static func magnification(
        distance: CGFloat, tileSize: CGFloat, magnified: CGFloat, reach: CGFloat = 2.5
    ) -> CGFloat {
        guard magnified > tileSize else { return tileSize }
        let radius = tileSize * reach
        let d = abs(distance)
        guard d < radius else { return tileSize }
        let falloff = (cos(d / radius * .pi) + 1) / 2
        return tileSize + (magnified - tileSize) * falloff
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        guard high >= low else { return low }
        return min(max(value, low), high)
    }
}
