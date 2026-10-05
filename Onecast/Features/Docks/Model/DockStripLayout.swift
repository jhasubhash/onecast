import CoreGraphics
import Foundation

/// Where each slot of a dock sits along its axis, with the magnifying lens applied.
///
/// Positions are in the dock's rest frame: its origin is the rim of the unmagnified dock, so a
/// tile or the plate grown by the lens may reach below zero or past the rest length. The lens is
/// anchored to the pointer: the point under it stays where it is, and the strip grows around it.
struct DockStripLayout: Equatable, Sendable {
    struct Tile: Equatable, Sendable {
        var along: CGFloat
        var length: CGFloat
        /// The extent across the axis; a magnified tile grows away from the dock's edge.
        var cross: CGFloat
        /// 1 at rest.
        var scale: CGFloat

        var end: CGFloat { along + length }
    }

    struct Slot: Equatable, Sendable {
        var extent: DockGeometry.Extent
        var magnifies: Bool
    }

    let tiles: [Tile]
    /// The plate's span along the axis: the rest length, grown by the lens.
    let plateStart: CGFloat
    let plateEnd: CGFloat
    let restLength: CGFloat
    let tileSize: CGFloat

    var gap: CGFloat { tileSize * DockGeometry.gapRatio }
    var inset: CGFloat { tileSize * DockGeometry.insetRatio }

    /// `pointer` is the pointer's position along the axis in the rest frame; nil, or a `lens`
    /// of 0, lays the strip out at rest. `scroll` shifts a rest layout along the axis.
    static func make(
        slots: [Slot], tileSize: CGFloat, magnifiedSize: CGFloat, pointer: CGFloat?,
        lens: CGFloat, scroll: CGFloat = 0
    ) -> DockStripLayout {
        let gap = tileSize * DockGeometry.gapRatio
        let inset = tileSize * DockGeometry.insetRatio
        var starts: [CGFloat] = []
        var lengths: [CGFloat] = []
        var cursor = inset
        for slot in slots {
            let length = slot.extent.length(tileSize: tileSize)
            starts.append(cursor)
            lengths.append(length)
            cursor += length + gap
        }
        let restLength = DockGeometry.length(of: slots.map(\.extent), tileSize: tileSize)

        guard let pointer, lens > 0, magnifiedSize > tileSize, !slots.isEmpty else {
            let tiles = slots.indices.map {
                Tile(along: starts[$0] - scroll, length: lengths[$0], cross: tileSize, scale: 1)
            }
            return DockStripLayout(
                tiles: tiles, plateStart: 0, plateEnd: restLength, restLength: restLength,
                tileSize: tileSize)
        }

        let scales = slots.indices.map { index -> CGFloat in
            guard slots[index].magnifies else { return 1 }
            let centre = starts[index] + lengths[index] / 2
            let size = DockGeometry.magnification(
                distance: centre - pointer, tileSize: tileSize, magnified: magnifiedSize)
            return 1 + lens * (size / tileSize - 1)
        }
        let extras = slots.indices.map { lengths[$0] * (scales[$0] - 1) }

        var anchor = slots.count - 1
        for index in slots.indices where pointer < starts[index] + lengths[index] + gap / 2 {
            anchor = index
            break
        }
        let fraction = min(max((pointer - starts[anchor]) / lengths[anchor], 0), 1)
        let grownBefore = extras[anchor] * fraction
        let grownAfter = extras[anchor] - grownBefore

        var tiles = slots.indices.map { index in
            Tile(
                along: starts[index], length: lengths[index] + extras[index],
                cross: slots[index].magnifies ? tileSize * scales[index] : tileSize,
                scale: scales[index])
        }
        tiles[anchor].along = starts[anchor] - grownBefore

        var shiftAfter = grownAfter
        for index in slots.indices where index > anchor {
            tiles[index].along = starts[index] + shiftAfter
            shiftAfter += extras[index]
        }
        var shiftBefore = grownBefore
        for index in slots.indices.reversed() where index < anchor {
            tiles[index].along = starts[index] + lengths[index] - shiftBefore - tiles[index].length
            shiftBefore += extras[index]
        }
        return DockStripLayout(
            tiles: tiles, plateStart: -shiftBefore, plateEnd: restLength + shiftAfter,
            restLength: restLength, tileSize: tileSize)
    }

    /// The tile holding the point `along` the axis and `fromEdge` the dock's edge-side rim.
    func tileIndex(along: CGFloat, fromEdge: CGFloat) -> Int? {
        let half = gap / 2
        for (index, tile) in tiles.enumerated() {
            guard along >= tile.along - half, along < tile.end + half else { continue }
            guard fromEdge >= 0, fromEdge <= inset * 2 + tile.cross else { return nil }
            return index
        }
        return nil
    }

    /// How many of the first `count` tiles sit wholly before `along`: where a drop would land.
    func insertionIndex(along: CGFloat, count: Int) -> Int {
        tiles.prefix(count).filter { $0.along + $0.length / 2 < along }.count
    }

    /// The position of the gap before tile `index` of the first `count`, for a drop marker.
    func insertionAlong(index: Int, count: Int) -> CGFloat {
        let pinned = min(count, tiles.count)
        guard !tiles.isEmpty else { return restLength / 2 }
        if index <= 0 { return tiles[0].along - gap / 2 }
        if index >= pinned { return tiles[max(pinned - 1, 0)].end + gap / 2 }
        return (tiles[index - 1].end + tiles[index].along) / 2
    }
}

extension DockSlot {
    /// Icons grow under the lens; widgets, spacers and dividers keep their size.
    var magnifies: Bool {
        switch self {
        case .pinned(let item, _):
            switch item.kind {
            case .spacer, .widget: false
            default: true
            }
        case .running, .minimized, .trash: true
        case .divider: false
        }
    }

    var stripSlot: DockStripLayout.Slot {
        DockStripLayout.Slot(extent: extent, magnifies: magnifies)
    }
}

/// The plate's corner, and the corner of a widget card inside it: the card's is the plate's less
/// the padding between them, so the two curves stay parallel.
enum DockPlateShape {
    /// The plate's corner as a share of its thickness; near a capsule's end.
    static let radiusRatio: CGFloat = 0.4

    static func plateRadius(tileSize: CGFloat) -> CGFloat {
        DockGeometry.thickness(tileSize: tileSize) * radiusRatio
    }

    static func cardRadius(tileSize: CGFloat) -> CGFloat {
        max(plateRadius(tileSize: tileSize) - tileSize * DockGeometry.insetRatio, 0)
    }
}
