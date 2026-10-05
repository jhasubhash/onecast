import Foundation

/// A fixed-capacity run of samples, oldest first, that a sparkline draws.
struct SystemSeries: Sendable, Equatable {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 2)
    }

    /// A negative or non-finite sample would draw below the baseline, so it reads as zero.
    mutating func append(_ value: Double) {
        values.append(value.isFinite ? max(value, 0) : 0)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    var latest: Double { values.last ?? 0 }

    var peak: Double { values.max() ?? 0 }

    /// Samples as fractions of `ceiling`; a young series is shorter than `capacity`.
    func normalized(ceiling: Double) -> [Double] {
        guard ceiling > 0 else { return values.map { _ in 0 } }
        return values.map { min($0 / ceiling, 1) }
    }

    /// The next 1, 2, 5 or 10 times a power of ten above `value` plus headroom.
    static func niceCeiling(for value: Double, floor: Double) -> Double {
        let target = max(value * 1.1, floor)
        guard target.isFinite, target > 0 else { return max(floor, 1) }
        let magnitude = pow(10, log10(target).rounded(.down))
        for step in [1.0, 2.0, 5.0, 10.0] where step * magnitude >= target {
            return step * magnitude
        }
        return 10 * magnitude
    }
}
