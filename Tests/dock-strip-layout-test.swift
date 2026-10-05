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
        growsEvenlyFromItsCentre()
        endsHoldStillOverTheMiddle()
        plateHoldsOneWidthWhileHovered()
        farTilesHoldStillWhileHovered()
        middleTileStaysUnderThePointer()
        nonMagnifyingSlotsKeepTheirSize()
        hitTestingFollowsTheLens()
        insertionIndexCountsPinnedCentres()
        insertionMarkerSitsInTheGap()
        slotMagnificationByKind()
        longWidgetMagnifiesAcrossItsBody()
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

    /// The bar grows by the same amount at both ends, wherever the pointer is.
    static func growsEvenlyFromItsCentre() {
        let rest = layout(tiles(6), pointer: nil)
        for pointer in stride(from: CGFloat(-20), through: rest.restLength + 20, by: 5) {
            let result = layout(tiles(6), pointer: pointer)
            near(-result.plateStart, result.plateEnd - rest.restLength, "even growth at \(pointer)", tolerance: 0.01)
        }
    }

    /// Over the middle of a long dock the ends do not move, so the bar never seems to breathe.
    static func endsHoldStillOverTheMiddle() {
        let rest = layout(tiles(14), pointer: nil)
        let from = rest.tiles[5].along, to = rest.tiles[8].end
        let starts = stride(from: from, through: to, by: 3).map { layout(tiles(14), pointer: $0).plateStart }
        let spread = (starts.max() ?? 0) - (starts.min() ?? 0)
        // The cosine lens's total ripples by under a point as it slides; under a pixel, unseen.
        expect(spread < 1, "the start barely moves while the pointer crosses the middle (spread \(spread))")
    }

    /// With its most growth given, the plate keeps one width for the whole sweep, ends included.
    static func plateHoldsOneWidthWhileHovered() {
        let rest = layout(tiles(8), pointer: nil)
        let pointers = Array(stride(from: CGFloat(0), through: rest.restLength, by: 4))
        let most = pointers.map { p in layout(tiles(8), pointer: p).tiles.reduce(0) { $0 + $1.length } }
            .max().map { $0 - tileSize * 8 } ?? 0
        let widths = pointers.map { p -> CGFloat in
            let grown = DockStripLayout.make(
                slots: tiles(8), tileSize: tileSize, magnifiedSize: magnified, pointer: p, lens: 1,
                plateGrowth: most)
            return grown.plateEnd - grown.plateStart
        }
        near((widths.max() ?? 0) - (widths.min() ?? 0), 0, "the plate's width never changes", tolerance: 0.001)
        near(widths.first ?? 0, rest.restLength + most, "it is the rest length plus the most growth")
        let half = DockStripLayout.make(
            slots: tiles(8), tileSize: tileSize, magnifiedSize: magnified, pointer: 100, lens: 0.5,
            plateGrowth: most)
        expect(half.plateEnd - half.plateStart < widths[0], "it eases in and out with the lens")
    }

    /// A tile well clear of the lens keeps exactly its place while the pointer moves elsewhere.
    static func farTilesHoldStillWhileHovered() {
        let count = 14
        let rest = layout(tiles(count), pointer: nil)
        let pointers = Array(stride(from: CGFloat(0), through: rest.restLength, by: 3))
        let most = pointers.map { p in layout(tiles(count), pointer: p).tiles.reduce(0) { $0 + $1.length } }
            .max().map { $0 - tileSize * CGFloat(count) } ?? 0
        func grown(_ pointer: CGFloat) -> DockStripLayout {
            DockStripLayout.make(
                slots: tiles(count), tileSize: tileSize, magnifiedSize: magnified, pointer: pointer,
                lens: 1, plateGrowth: most)
        }
        let late = pointers.filter { $0 > rest.tiles[6].along }.map { grown($0).tiles[0].along }
        near((late.max() ?? 0) - (late.min() ?? 0), 0, "the first tile never moves", tolerance: 0.001)
        let early = pointers.filter { $0 < rest.tiles[7].end }.map { grown($0).tiles[count - 1].along }
        near((early.max() ?? 0) - (early.min() ?? 0), 0, "nor does the last", tolerance: 0.001)
        let gap = tileSize * DockGeometry.gapRatio
        for pointer in pointers {
            let result = grown(pointer)
            for index in 1..<count {
                expect(
                    result.tiles[index].along - result.tiles[index - 1].end >= gap - 0.001,
                    "tiles never close their gap at \(pointer)")
            }
            expect(
                result.tiles[0].along >= result.plateStart && result.tiles[count - 1].end <= result.plateEnd,
                "tiles stay on the plate at \(pointer)")
        }
    }

    /// At a middle tile's centre the lens is symmetric, so that tile stays centred under the pointer.
    static func middleTileStaysUnderThePointer() {
        let rest = layout(tiles(9), pointer: nil)
        let pointer = rest.tiles[4].along + tileSize / 2
        let tile = layout(tiles(9), pointer: pointer).tiles[4]
        near(tile.along + tile.length / 2, pointer, "the hovered tile is centred on the pointer")
        let beyond = layout(tiles(4), pointer: rest.restLength + 500)
        expect(beyond.tiles.count == 4, "a far pointer still lays out")
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
        expect(DockSlot.pinned(widget, running: nil).magnifies, "a widget magnifies too")
        expect(DockSlot.trash.magnifies, "the trash magnifies")
        expect(!DockSlot.divider("running").magnifies, "a divider does not")
        expect(
            DockSlot.trash.stripSlot == DockStripLayout.Slot(extent: .tile, magnifies: true),
            "a strip slot pairs extent and magnification")
    }

    /// A long widget is fully grown anywhere over its body, by no more length than an icon gains.
    static func longWidgetMagnifiesAcrossItsBody() {
        let slots: [DockStripLayout.Slot] = [
            .init(extent: .tile, magnifies: true), .init(extent: .span(4), magnifies: true),
        ]
        let rest = layout(slots, pointer: nil)
        let wide = rest.tiles[1]
        let iconGrowth = magnified - tileSize
        for fraction in [CGFloat(0.15), 0.5, 0.85] {
            let over = layout(slots, pointer: wide.along + wide.length * fraction)
            near(over.tiles[1].length - wide.length, iconGrowth, "grown by one icon's worth at \(fraction)")
        }
        let first = layout(slots, pointer: rest.tiles[0].along + rest.tiles[0].length / 2)
        near(first.tiles[0].scale, magnified / tileSize, "a plain tile still peaks at its centre")
        expect(first.tiles[1].scale > 1, "a widget near the pointer grows a little")
        near(rest.depth, DockGeometry.thickness(tileSize: tileSize), "at rest the strip is as deep as the plate")
        near(first.depth, magnified + 2 * rest.inset, "under the lens it reaches the tallest tile")
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
            near(card, size * DockPlateShape.cardRadiusRatio, "card radius follows the tile size at \(size)")
            expect(card > 0 && card <= size * 0.2, "a card is rounded, never pill-shaped, at \(size)")
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
