// Standalone test for the shelf's stack and shake gesture, compiling the real sources.
import Foundation

@main
@MainActor
struct ShelfTests {
    static var failures = 0
    static var passes = 0

    static let report = URL(fileURLWithPath: "/scratch/report.pdf")
    static let site = URL(string: "https://example.com/page")!

    static func main() {
        addsInDropOrder()
        eachDropIsItsOwnGroup()
        lateDeliveryJoinsItsDrop()
        sameFileTwiceIsOneItem()
        removingTheLastItemDropsItsGroup()
        groupTitlesByItsOnlyItemOrItsCount()
        summaryNamesOneKindOrItems()
        textTitleIsItsFirstLine()
        returnGoesBackWhereItWas()
        returnBesideAClashGetsANumber()
        clickSelectsOne()
        commandClickToggles()
        shiftClickTakesTheRun()
        pressOnSelectionKeepsItForADrag()
        dragFromOutsideTheSelectionTakesOnlyThatRow()
        threeQuickReversalsAreAShake()
        smallJitterIsNoShake()
        slowSweepsAreNoShake()
        shakeFiresOnceThenStartsOver()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func items(_ groups: [ShelfGroup]) -> [ShelfItem.Content] {
        groups.flatMap(\.items).map(\.content)
    }

    static func addsInDropOrder() {
        let groups = ShelfStack.adding(made([.file(report), .link(site), .text("hi")]), as: UUID(), to: [])
        expect(groups.count == 1, "one drop is one group")
        expect(
            items(groups) == [.file(report), .link(site), .text("hi")],
            "a drop's contents keep the order they came in")
    }

    static func eachDropIsItsOwnGroup() {
        let first = ShelfStack.adding(made([.file(report)]), as: UUID(), to: [])
        let second = ShelfStack.adding(made([.link(site), .text("x")]), as: UUID(), to: first)
        expect(second.map(\.items.count) == [1, 2], "a second drop starts a second group")
    }

    static func lateDeliveryJoinsItsDrop() {
        let id = UUID()
        let first = ShelfStack.adding(made([.file(report)]), as: id, to: [])
        let joined = ShelfStack.adding(made([.text("promised")]), as: id, to: first)
        expect(joined.count == 1 && joined[0].items.count == 2, "a promised file joins the drop it came with")
    }

    static func sameFileTwiceIsOneItem() {
        let first = ShelfStack.adding(made([.file(report)]), as: UUID(), to: [])
        let again = ShelfStack.adding(
            made([.file(URL(fileURLWithPath: "/scratch/./report.pdf"))]), as: UUID(), to: first)
        expect(again == first, "a file already held is not added again, nor makes an empty group")
    }

    static func removingTheLastItemDropsItsGroup() {
        let groups = ShelfStack.adding(made([.file(report)]), as: UUID(), to: [])
        let pair = ShelfStack.adding(made([.link(site), .text("x")]), as: UUID(), to: groups)
        let left = ShelfStack.removing([pair[0].items[0].id, pair[1].items[0].id], from: pair)
        expect(left.count == 1 && left[0].items.map(\.content) == [.text("x")], "an emptied group goes")
    }

    static func groupTitlesByItsOnlyItemOrItsCount() {
        let groups = ShelfStack.adding(made([.file(report)]), as: UUID(), to: [])
        expect(groups[0].title == "report.pdf", "a group of one shows that item's name")
        let pair = ShelfStack.adding(made([.link(site), .text("x")]), as: UUID(), to: [])
        expect(pair[0].title == "2 Items", "a larger group shows its count")
    }

    static func summaryNamesOneKindOrItems() {
        expect(ShelfStack.summary(of: []) == "Shelf", "an empty shelf is just the Shelf")
        expect(ShelfStack.summary(of: made([.file(report)])) == "1 File", "one file reads singular")
        expect(
            ShelfStack.summary(of: made([.file(report), .link(site), .text("x")])) == "3 Items",
            "mixed kinds read as items")
    }

    static func textTitleIsItsFirstLine() {
        expect(
            ShelfItem(.text("  first line\nsecond")).title == "first line", "text titles by its first line")
        expect(ShelfItem(.link(site)).title == "example.com", "a link titles by its host")
    }

    static func made(_ contents: [ShelfItem.Content]) -> [ShelfItem] {
        contents.map { ShelfItem($0) }
    }

    static func returnGoesBackWhereItWas() {
        expect(
            ShelfReturn.destination(for: report) { _ in false } == report,
            "a file leaving the shelf goes back to the path it came from")
    }

    static func returnBesideAClashGetsANumber() {
        let taken: Set<String> = ["/scratch/report.pdf", "/scratch/report 2.pdf"]
        let back = ShelfReturn.destination(for: report) { taken.contains($0.path) }
        expect(back.path == "/scratch/report 3.pdf", "a file now in its old spot is never overwritten")
        let folder = URL(fileURLWithPath: "/scratch/Photos")
        expect(
            ShelfReturn.destination(for: folder) { $0 == folder }.path == "/scratch/Photos 2",
            "a name without an extension numbers at its end")
    }

    static let rows = (0..<4).map { _ in UUID() }

    static func clickSelectsOne() {
        var selection = ShelfSelection()
        selection.press(rows[1], in: rows, command: false, shift: false)
        selection.press(rows[2], in: rows, command: false, shift: false)
        expect(selection.ids == [rows[2]], "a plain click picks just that row")
    }

    static func commandClickToggles() {
        var selection = ShelfSelection()
        selection.press(rows[0], in: rows, command: false, shift: false)
        selection.press(rows[2], in: rows, command: true, shift: false)
        expect(selection.ids == [rows[0], rows[2]], "⌘-click adds a row")
        selection.press(rows[0], in: rows, command: true, shift: false)
        expect(selection.ids == [rows[2]], "⌘-click on a picked row drops it")
    }

    static func shiftClickTakesTheRun() {
        var selection = ShelfSelection()
        selection.press(rows[3], in: rows, command: false, shift: false)
        selection.press(rows[1], in: rows, command: false, shift: true)
        expect(selection.ids == Set(rows[1...3]), "⇧-click takes every row between")
    }

    static func pressOnSelectionKeepsItForADrag() {
        var selection = ShelfSelection()
        selection.selectAll(rows)
        selection.press(rows[1], in: rows, command: false, shift: false)
        expect(selection.dragged(from: rows[1], in: rows) == rows, "a drag from the selection takes all of it")
        selection.click(rows[1])
        expect(selection.ids == [rows[1]], "a click without a drag narrows to that row")
    }

    static func dragFromOutsideTheSelectionTakesOnlyThatRow() {
        var selection = ShelfSelection()
        selection.press(rows[0], in: rows, command: false, shift: false)
        expect(selection.dragged(from: rows[3], in: rows) == [rows[3]], "an unpicked row drags alone")
    }

    static func sweep(_ detector: inout ShakeDetector, _ xs: [Double], step: TimeInterval) -> Bool {
        var fired = false
        for (index, x) in xs.enumerated() where detector.record(x: x, at: Double(index) * step) {
            fired = true
        }
        return fired
    }

    static func threeQuickReversalsAreAShake() {
        var detector = ShakeDetector()
        expect(
            sweep(&detector, [0, 60, 0, 60, 0, 60], step: 0.05),
            "three quick reversals of a deliberate sweep open the shelf")
    }

    static func smallJitterIsNoShake() {
        var detector = ShakeDetector()
        expect(
            !sweep(&detector, [0, 10, 0, 10, 0, 10, 0, 10, 0], step: 0.03),
            "a hand's jitter along the drag is no shake")
    }

    static func slowSweepsAreNoShake() {
        var detector = ShakeDetector()
        expect(
            !sweep(&detector, [0, 60, 0, 60, 0, 60], step: 0.5),
            "reversals spread over seconds are a wandering drag, not a shake")
    }

    static func shakeFiresOnceThenStartsOver() {
        var detector = ShakeDetector()
        var fires = 0
        for (index, x) in [0.0, 60, 0, 60, 0, 60, 0].enumerated()
        where detector.record(x: x, at: Double(index) * 0.05) {
            fires += 1
        }
        expect(fires == 1, "one shake fires once, not on every reversal after it")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
