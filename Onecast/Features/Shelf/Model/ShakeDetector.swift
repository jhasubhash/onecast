import Foundation

/// Spots a shake in a drag: quick sideways sweeps that reverse, each long enough to be deliberate.
struct ShakeDetector {
    var minimumSweep: Double = 30
    var reversalsNeeded = 3
    var window: TimeInterval = 0.7

    private var origin: Double?
    private var extreme = 0.0
    private var direction = 0.0
    private var reversals: [TimeInterval] = []

    mutating func reset() {
        origin = nil
        direction = 0
        reversals = []
    }

    /// True on the move that completes a shake, after which it starts over.
    mutating func record(x: Double, at time: TimeInterval) -> Bool {
        guard let origin else {
            origin = x
            extreme = x
            return false
        }
        if direction == 0 {
            guard abs(x - origin) >= minimumSweep else { return false }
            direction = x > origin ? 1 : -1
            extreme = x
            return false
        }
        if (x - extreme) * direction > 0 {
            extreme = x
            return false
        }
        guard (extreme - x) * direction >= minimumSweep else { return false }
        direction = -direction
        extreme = x
        reversals = reversals.filter { time - $0 <= window } + [time]
        guard reversals.count >= reversalsNeeded else { return false }
        reset()
        return true
    }
}
