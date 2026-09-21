// The token gate authorises a helper call only while its route is armed and its token is unexpired.
import Foundation

@main
@MainActor
struct ComputerUseTokenLedgerTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("✗ \(message)")
        }
    }

    static func main() {
        refusesAnUnknownToken()
        acceptsAnArmedTokenWhileFresh()
        refusesADisarmedRoute()
        readsArmingLiveNotSnapshotted()
        expiresPastItsLifetime()
        evictsOldestPastCapacity()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func refusesAnUnknownToken() {
        let ledger = ComputerUseTokenLedger()
        expect(!ledger.authorizes("nope", now: t0), "a token never issued is refused")
    }

    static func acceptsAnArmedTokenWhileFresh() {
        var ledger = ComputerUseTokenLedger(lifetime: 100)
        ledger.issue("t", armed: { true }, now: t0)
        expect(ledger.authorizes("t", now: t0), "an armed token authorises at issuance")
        expect(
            ledger.authorizes("t", now: t0 + 99), "an armed token authorises up to its lifetime")
    }

    static func refusesADisarmedRoute() {
        var ledger = ComputerUseTokenLedger()
        ledger.issue("t", armed: { false }, now: t0)
        expect(!ledger.authorizes("t", now: t0), "a known token on a disarmed route is refused")
    }

    /// The predicate is read on every call, so a route disarmed after issuance locks its helper out.
    static func readsArmingLiveNotSnapshotted() {
        var armed = true
        var ledger = ComputerUseTokenLedger()
        ledger.issue("t", armed: { armed }, now: t0)
        expect(ledger.authorizes("t", now: t0), "armed at first call")
        armed = false
        expect(!ledger.authorizes("t", now: t0), "disarming after issuance refuses at once")
    }

    static func expiresPastItsLifetime() {
        var ledger = ComputerUseTokenLedger(lifetime: 100)
        ledger.issue("t", armed: { true }, now: t0)
        expect(!ledger.authorizes("t", now: t0 + 100), "a token is refused once its lifetime elapses")
        expect(
            !ledger.authorizes("t", now: t0 + 10_000),
            "a long-stale token stays refused")
    }

    static func evictsOldestPastCapacity() {
        var ledger = ComputerUseTokenLedger(capacity: 2, lifetime: 1000)
        ledger.issue("a", armed: { true }, now: t0)
        ledger.issue("b", armed: { true }, now: t0)
        ledger.issue("c", armed: { true }, now: t0)
        expect(!ledger.authorizes("a", now: t0), "the oldest token is evicted past capacity")
        expect(ledger.authorizes("b", now: t0), "a token within capacity survives")
        expect(ledger.authorizes("c", now: t0), "the newest token survives")
    }
}
