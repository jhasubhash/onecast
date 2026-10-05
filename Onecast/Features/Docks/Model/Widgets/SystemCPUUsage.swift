import Foundation

/// CPU load derived from two snapshots of the kernel's per-core tick counters.
struct SystemCPUUsage: Sendable, Equatable {
    /// One core's cumulative ticks, as `host_processor_info` reports them: 32-bit and wrapping.
    struct Ticks: Sendable, Equatable {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    /// Busy share across every core, 0...1.
    let overall: Double
    /// Busy share spent in user code (nice included), 0...1.
    let user: Double
    /// Busy share spent in the kernel, 0...1.
    let system: Double
    /// Each core's busy share, 0...1, in core order.
    let cores: [Double]

    /// Nil when the snapshots do not describe the same cores or no tick passed between them.
    static func between(_ previous: [Ticks], _ current: [Ticks]) -> SystemCPUUsage? {
        guard !current.isEmpty, previous.count == current.count else { return nil }
        var cores: [Double] = []
        var busy: UInt64 = 0
        var total: UInt64 = 0
        var userTicks: UInt64 = 0
        var systemTicks: UInt64 = 0
        for (before, after) in zip(previous, current) {
            let user = UInt64(after.user &- before.user)
            let system = UInt64(after.system &- before.system)
            let nice = UInt64(after.nice &- before.nice)
            let idle = UInt64(after.idle &- before.idle)
            let coreBusy = user + system + nice
            let coreTotal = coreBusy + idle
            cores.append(coreTotal == 0 ? 0 : Double(coreBusy) / Double(coreTotal))
            busy += coreBusy
            total += coreTotal
            userTicks += user + nice
            systemTicks += system
        }
        guard total > 0 else { return nil }
        return SystemCPUUsage(
            overall: Double(busy) / Double(total), user: Double(userTicks) / Double(total),
            system: Double(systemTicks) / Double(total), cores: cores)
    }
}
