import Foundation

@main
@MainActor
struct DockWidgetsPersonalTests {
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

    static func main() {
        HydrationChecks.run()
        WeatherChecks.run()
        AIUsageChecks.run()
        StockChecks.run()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
