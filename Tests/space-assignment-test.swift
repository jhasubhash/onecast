import Foundation

@main
struct SpaceAssignmentTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // The main display's first space has an empty UUID, exactly as com.apple.spaces stores it.
        let spaces = [["A", "", "B"], ["C", "D"]]

        check("no binding is None", SpaceAssignment.resolve(binding: nil, displaySpaces: spaces) == .none)
        check(
            "AllSpaces is All Desktops",
            SpaceAssignment.resolve(binding: "AllSpaces", displaySpaces: spaces) == .allDesktops)
        check(
            "an empty UUID is the main display",
            SpaceAssignment.resolve(binding: "", displaySpaces: spaces) == .display(0))
        check(
            "a second display's space resolves to it",
            SpaceAssignment.resolve(binding: "D", displaySpaces: spaces) == .display(1))
        check(
            "a removed space is None",
            SpaceAssignment.resolve(binding: "Z", displaySpaces: spaces) == .none)

        check(
            "two displays list four choices in the Dock's order",
            SpaceAssignment.choices(displayCount: 2) == [.allDesktops, .display(0), .display(1), .none])
        check(
            "no displays still offers one desktop",
            SpaceAssignment.choices(displayCount: 0) == [.allDesktops, .display(0), .none])

        check("one display says This Desktop", SpaceAssignment.display(0).title(displayCount: 1) == "This Desktop")
        check(
            "several displays are numbered from one",
            SpaceAssignment.display(1).title(displayCount: 2) == "Desktop on Display 2")

        let current = ["", "C"]
        check("All Desktops stores AllSpaces", SpaceAssignment.allDesktops.bindingValue(currentSpaces: current) == "AllSpaces")
        check("a display stores its current space", SpaceAssignment.display(1).bindingValue(currentSpaces: current) == "C")
        check("None removes the binding", SpaceAssignment.none.bindingValue(currentSpaces: current) == nil)
        check("a missing display removes it", SpaceAssignment.display(5).bindingValue(currentSpaces: current) == nil)

        // Whatever is stored must read back as the same choice, or the checkmark lands elsewhere.
        for choice in SpaceAssignment.choices(displayCount: 2) {
            let stored = choice.bindingValue(currentSpaces: current)
            check(
                "\(choice) round-trips",
                SpaceAssignment.resolve(binding: stored, displaySpaces: [["", "A"], ["C"]]) == choice)
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) failed")
        if failures > 0 { exit(1) }
    }
}
