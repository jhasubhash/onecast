import CoreGraphics
import Foundation

/// Where each slot of a dock sits along its axis, with the magnifying lens applied.
///
/// Positions are in the dock's rest frame: its origin is the rim of the unmagnified dock, so a
/// tile or the plate grown by the lens may reach below zero or past the rest length. The lens
/// grows the strip evenly from its centre, as the macOS Dock does, so its ends hold still.
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
    /// How far from the edge-side rim the strip reaches: the rest thickness, or the tallest tile.
    var depth: CGFloat { 2 * inset + (tiles.map(\.cross).max() ?? tileSize) }

    /// `pointer` is the pointer's position along the axis in the rest frame; nil, or a `lens`
    /// of 0, lays the strip out at rest. `scroll` shifts a rest layout along the axis.
    /// `plateGrowth` is the most the lens ever adds; the plate takes all of it while hovered.
    static func make(
        slots: [Slot], tileSize: CGFloat, magnifiedSize: CGFloat, pointer: CGFloat?,
        lens: CGFloat, scroll: CGFloat = 0, plateGrowth: CGFloat = 0
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
            // A long widget is at full size anywhere over its body, not only at its centre.
            let body = max(lengths[index] - tileSize, 0) / 2
            let size = DockGeometry.magnification(
                distance: max(abs(centre - pointer) - body, 0), tileSize: tileSize,
                magnified: magnifiedSize)
            // Every slot grows by at most what one icon does, so a long widget never drags the strip.
            let share = tileSize / max(lengths[index], tileSize)
            return 1 + lens * (size / tileSize - 1) * share
        }
        let extras = slots.indices.map { lengths[$0] * (scales[$0] - 1) }

        let total = extras.reduce(0, +)
        // The plate holds one width for the whole hover, so its ends never creep as the lens moves.
        let half = max(plateGrowth * lens, total) / 2
        // Unused room sits at the pointer: earlier tiles keep to the start, later ones to the end.
        let slack = 2 * half - total
        var grown: CGFloat = 0
        let tiles = slots.indices.map { index in
            let centre = starts[index] + lengths[index] / 2
            let towardEnd = min(max((centre - pointer) / tileSize + 0.5, 0), 1)
            let tile = Tile(
                along: starts[index] - half + grown + slack * towardEnd,
                length: lengths[index] + extras[index],
                cross: slots[index].magnifies ? tileSize * scales[index] : tileSize,
                scale: scales[index])
            grown += extras[index]
            return tile
        }
        return DockStripLayout(
            tiles: tiles, plateStart: -half, plateEnd: restLength + half,
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
    /// Icons and widgets grow under the lens; spacers and dividers keep their size.
    var magnifies: Bool {
        switch self {
        case .pinned(let item, _):
            switch item.kind {
            case .spacer: false
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
    /// A widget card's corner as a share of the tile size; Dockset's cards sit near a sixth.
    static let cardRadiusRatio: CGFloat = 0.18

    static func plateRadius(tileSize: CGFloat) -> CGFloat {
        cardRadius(tileSize: tileSize) + tileSize * DockGeometry.insetRatio
    }

    static func cardRadius(tileSize: CGFloat) -> CGFloat {
        tileSize * cardRadiusRatio
    }
}
