import CoreGraphics
import Foundation

@main
@MainActor
struct DockStripLayoutTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ message: String, tolerance: CGFloat = 0.001) {
        expect(abs(a - b) < tolerance, "\(message) (got \(a), wanted \(b))")
    }

    static let tileSize: CGFloat = 48
    static let magnified: CGFloat = 96

    static func tiles(_ count: Int, magnifies: Bool = true) -> [DockStripLayout.Slot] {
        Array(repeating: DockStripLayout.Slot(extent: .tile, magnifies: magnifies), count: count)
    }

    static func layout(
        _ slots: [DockStripLayout.Slot], pointer: CGFloat?, lens: CGFloat = 1, scroll: CGFloat = 0
    ) -> DockStripLayout {
        DockStripLayout.make(
            slots: slots, tileSize: tileSize, magnifiedSize: magnified, pointer: pointer,
            lens: lens, scroll: scroll)
    }

    static func main() {
        restLayoutMatchesGeometry()
        scrollShiftsRestLayout()
        lensOffOrPointerAbsentIsRest()
        magnifiedTileReachesFullSize()
        plateGrowsByTheSumOfTheExtras()
        tilesNeverOverlapOrLoseTheirGap()
        pointerStaysOnTheSameFractionOfItsTile()
        edgesGrowOnlyInward()
        nonMagnifyingSlotsKeepTheirSize()
        hitTestingFollowsTheLens()
        insertionIndexCountsPinnedCentres()
        insertionMarkerSitsInTheGap()
        slotMagnificationByKind()
        popupsSitBesideTheirAnchor()
        popupsStayOnScreen()
        cardCornerIsConcentricWithThePlate()
        handleSlotEndsTheStrip()

        print("dock-strip-layout-test: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func restLayoutMatchesGeometry() {
        let slots = tiles(3)
        let result = layout(slots, pointer: nil)
        let inset = tileSize * DockGeometry.insetRatio
        let gap = tileSize * DockGeometry.gapRatio
        near(result.tiles[0].along, inset, "first tile starts at the rim inset")
        near(result.tiles[1].along, inset + tileSize + gap, "second tile follows the gap")
        near(
            result.restLength, DockGeometry.length(of: slots.map(\.extent), tileSize: tileSize),
            "rest length is the geometry's length")
        near(result.plateStart, 0, "plate starts at zero at rest")
        near(result.plateEnd, result.restLength, "plate ends at the rest length at rest")
        expect(result.tiles.allSatisfy { $0.scale == 1 && $0.cross == tileSize }, "rest scale is 1")
    }

    static func scrollShiftsRestLayout() {
        let rest = layout(tiles(3), pointer: nil)
        let scrolled = layout(tiles(3), pointer: nil, scroll: 20)
        near(scrolled.tiles[1].along, rest.tiles[1].along - 20, "scroll moves tiles back")
    }

    static func lensOffOrPointerAbsentIsRest() {
        let rest = layout(tiles(4), pointer: nil)
        expect(layout(tiles(4), pointer: 100, lens: 0) == rest, "lens 0 is rest")
        expect(
            DockStripLayout.make(
                slots: tiles(4), tileSize: tileSize, magnifiedSize: tileSize, pointer: 100,
                lens: 1) == rest, "magnified size at tile size is rest")
        expect(layout([], pointer: 10).tiles.isEmpty, "an empty dock has no tiles")
    }

    static func magnifiedTileReachesFullSize() {
        let rest = layout(tiles(5), pointer: nil)
        let centre = rest.tiles[2].along + tileSize / 2
        let result = layout(tiles(5), pointer: centre)
        near(result.tiles[2].length, magnified, "the tile under the pointer is fully magnified")
        near(result.tiles[2].cross, magnified, "its cross extent grows with it")
        near(result.tiles[2].scale, 2, "its scale is the ratio")
        near(layout(tiles(5), pointer: centre, lens: 0.5).tiles[2].length, 72, "half a lens is halfway")
    }

    static func plateGrowsByTheSumOfTheExtras() {
        let rest = layout(tiles(7), pointer: nil)
        for pointer in stride(from: CGFloat(0), through: rest.restLength, by: 7) {
            let result = layout(tiles(7), pointer: pointer)
            let extras = result.tiles.reduce(0) { $0 + $1.length } - tileSize * 7
            near(
                result.plateEnd - result.plateStart, rest.restLength + extras,
                "plate grows by the extras at \(pointer)", tolerance: 0.01)
            near(result.tiles[0].along - result.plateStart, rest.tiles[0].along,
                "the leading inset is kept at \(pointer)", tolerance: 0.01)
            near(result.plateEnd - result.tiles[6].end, rest.restLength - rest.tiles[6].end,
                "the trailing inset is kept at \(pointer)", tolerance: 0.01)
        }
    }

    static func tilesNeverOverlapOrLoseTheirGap() {
        let gap = tileSize * DockGeometry.gapRatio
        let rest = layout(tiles(6), pointer: nil)
        for pointer in stride(from: CGFloat(-20), through: rest.restLength + 20, by: 5) {
            let result = layout(tiles(6), pointer: pointer)
            for index in 1..<result.tiles.count {
                let space = result.tiles[index].along - result.tiles[index - 1].end
                near(space, gap, "gap kept between \(index - 1) and \(index) at \(pointer)", tolerance: 0.01)
            }
        }
    }

    static func pointerStaysOnTheSameFractionOfItsTile() {
        let rest = layout(tiles(5), pointer: nil)
        let pointer = rest.tiles[2].along + tileSize * 0.25
        let result = layout(tiles(5), pointer: pointer)
        let tile = result.tiles[2]
        near((pointer - tile.along) / tile.length, 0.25, "the pointer keeps its place on the tile")
        near(tile.along + tile.length * 0.25, pointer, "so the tile stays under it")
    }

    static func edgesGrowOnlyInward() {
        let rest = layout(tiles(4), pointer: nil)
        let atStart = layout(tiles(4), pointer: rest.tiles[0].along)
        near(atStart.plateStart, 0, "pointer at the first tile's start leaves the start put")
        expect(atStart.plateEnd > rest.restLength, "the plate grows away from the pointer")
        let atEnd = layout(tiles(4), pointer: rest.tiles[3].end)
        near(atEnd.plateEnd, rest.restLength, "pointer at the last tile's end leaves the end put")
        expect(atEnd.plateStart < 0, "the plate grows toward the start")
        let beyond = layout(tiles(4), pointer: rest.restLength + 500)
        expect(beyond.tiles.count == 4 && beyond.plateEnd >= rest.restLength, "a far pointer still lays out")
    }

    static func nonMagnifyingSlotsKeepTheirSize() {
        let slots: [DockStripLayout.Slot] = [
            .init(extent: .tile, magnifies: true),
            .init(extent: .span(2), magnifies: false),
            .init(extent: .spacer(.small), magnifies: false),
            .init(extent: .divider, magnifies: false),
            .init(extent: .tile, magnifies: true),
        ]
        let rest = layout(slots, pointer: nil)
        let result = layout(slots, pointer: rest.tiles[0].along + tileSize / 2)
        for index in 1...3 {
            near(result.tiles[index].length, rest.tiles[index].length, "slot \(index) keeps its length")
            near(result.tiles[index].cross, tileSize, "slot \(index) keeps its cross extent")
        }
        expect(result.tiles[1].along > rest.tiles[1].along, "but it is pushed along by the growth")
    }

    static func hitTestingFollowsTheLens() {
        let rest = layout(tiles(3), pointer: nil)
        let centre = rest.tiles[1].along + tileSize / 2
        near(CGFloat(rest.tileIndex(along: centre, fromEdge: 20) ?? -1), 1, "rest hit")
        expect(rest.tileIndex(along: centre, fromEdge: -5) == nil, "outside the rim misses")
        expect(rest.tileIndex(along: centre, fromEdge: 200) == nil, "far above the dock misses")
        let grown = layout(tiles(3), pointer: centre)
        expect(grown.tileIndex(along: centre, fromEdge: 90) == 1, "a magnified tile is taller")
        expect(rest.tileIndex(along: -50, fromEdge: 10) == nil, "off the strip misses")
        let between = (rest.tiles[0].end + rest.tiles[1].along) / 2
        expect(rest.tileIndex(along: between, fromEdge: 10) != nil, "a gap belongs to a neighbour")
    }

    static func insertionIndexCountsPinnedCentres() {
        let rest = layout(tiles(5), pointer: nil)
        near(CGFloat(rest.insertionIndex(along: -10, count: 3)), 0, "before everything")
        near(CGFloat(rest.insertionIndex(along: rest.tiles[0].end + 1, count: 3)), 1, "past one centre")
        near(CGFloat(rest.insertionIndex(along: rest.tiles[4].end, count: 3)), 3, "capped at the pinned count")
        near(CGFloat(rest.insertionIndex(along: 100, count: 0)), 0, "nothing pinned inserts first")
    }

    static func insertionMarkerSitsInTheGap() {
        let rest = layout(tiles(4), pointer: nil)
        let gap = tileSize * DockGeometry.gapRatio
        near(rest.insertionAlong(index: 0, count: 4), rest.tiles[0].along - gap / 2, "marker before the first")
        near(
            rest.insertionAlong(index: 2, count: 4), (rest.tiles[1].end + rest.tiles[2].along) / 2,
            "marker between two")
        near(rest.insertionAlong(index: 4, count: 4), rest.tiles[3].end + gap / 2, "marker after the last")
        near(rest.insertionAlong(index: 2, count: 2), rest.tiles[1].end + gap / 2, "marker ends the pinned run")
    }

    static func slotMagnificationByKind() {
        let app = DockItem(kind: .app(DockAppReference(bundleID: "a", path: "/a")))
        let spacer = DockItem(kind: .spacer(.regular))
        let widget = DockItem(kind: .widget(DockWidgetReference(widgetID: "builtin.x")))
        expect(DockSlot.pinned(app, running: nil).magnifies, "an app magnifies")
        expect(!DockSlot.pinned(spacer, running: nil).magnifies, "a spacer does not")
        expect(!DockSlot.pinned(widget, running: nil).magnifies, "a widget does not")
        expect(DockSlot.trash.magnifies, "the trash magnifies")
        expect(!DockSlot.divider("running").magnifies, "a divider does not")
        expect(
            DockSlot.trash.stripSlot == DockStripLayout.Slot(extent: .tile, magnifies: true),
            "a strip slot pairs extent and magnification")
    }

    static let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    static func popup(
        _ edge: DockEdge, anchor: CGRect, size: CGSize = CGSize(width: 200, height: 100)
    ) -> CGRect {
        DockPopupPlacement.frame(
            size: size, anchor: anchor, edge: edge, visible: screen, gap: 8, margin: 8)
    }

    static func popupsSitBesideTheirAnchor() {
        let anchor = CGRect(x: 400, y: 10, width: 50, height: 50)
        let above = popup(.bottom, anchor: anchor)
        near(above.minY, anchor.maxY + 8, "a bottom dock's popup sits above its tile")
        near(above.midX, anchor.midX, "and is centred on it")
        let side = CGRect(x: 6, y: 300, width: 50, height: 50)
        let right = popup(.left, anchor: side)
        near(right.minX, side.maxX + 8, "a left dock's popup sits to its right")
        near(right.midY, side.midY, "centred along the edge")
        let far = CGRect(x: 944, y: 300, width: 50, height: 50)
        let left = popup(.right, anchor: far)
        near(left.maxX, far.minX - 8, "a right dock's popup sits to its left")
    }

    static func popupsStayOnScreen() {
        let corner = popup(.bottom, anchor: CGRect(x: 0, y: 10, width: 50, height: 50))
        near(corner.minX, 8, "a popup at the screen's start is pulled in by the margin")
        let end = popup(.bottom, anchor: CGRect(x: 960, y: 10, width: 50, height: 50))
        near(end.maxX, 992, "and at its end")
        let tall = popup(
            .left, anchor: CGRect(x: 6, y: 790, width: 50, height: 50),
            size: CGSize(width: 100, height: 300))
        near(tall.maxY, 792, "a popup near the top is pulled down")
        let fitted = DockPopupPlacement.fittedSize(
            CGSize(width: 2000, height: 3000), in: screen, margin: 8)
        near(fitted.width, 984, "an oversized popup is cut to the screen's width")
        near(fitted.height, 784, "and height")
        let kept = DockPopupPlacement.fittedSize(
            CGSize(width: 100, height: 100), in: screen, margin: 8)
        near(kept.width, 100, "a small popup is left alone")
    }

    static func cardCornerIsConcentricWithThePlate() {
        for size in [CGFloat(24), 48, 96, 128] {
            let plate = DockPlateShape.plateRadius(tileSize: size)
            let card = DockPlateShape.cardRadius(tileSize: size)
            near(plate - card, size * DockGeometry.insetRatio, "padding is the radii's difference at \(size)")
            near(plate, DockGeometry.thickness(tileSize: size) * DockPlateShape.radiusRatio, "plate radius follows thickness at \(size)")
            expect(card > 0 && card < size / 2, "a card is rounded but never a circle at \(size)")
        }
    }

    static func handleSlotEndsTheStrip() {
        let handle = DockStripLayout.Slot(extent: .spacer(.small), magnifies: false)
        let withHandle = layout(tiles(3) + [handle], pointer: nil)
        let without = layout(tiles(3), pointer: nil)
        let gap = tileSize * DockGeometry.gapRatio
        near(withHandle.tiles[3].along, without.tiles[2].end + gap, "the handle follows the last tile")
        near(withHandle.restLength - without.restLength, tileSize * 0.5 + gap, "and adds a half tile and a gap")
        let lensed = layout(tiles(3) + [handle], pointer: withHandle.tiles[1].along + tileSize / 2)
        near(lensed.tiles[3].length, withHandle.tiles[3].length, "the lens leaves the handle its size")
    }
}
