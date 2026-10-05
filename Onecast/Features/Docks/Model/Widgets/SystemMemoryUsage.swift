import Foundation

/// Memory figures as Activity Monitor groups them, from the kernel's page counters.
struct SystemMemoryUsage: Sendable, Equatable {
    /// The `vm_statistics64` counters this needs, in pages.
    struct Pages: Sendable, Equatable {
        let free: UInt64
        let wired: UInt64
        let compressed: UInt64
        let purgeable: UInt64
        /// Anonymous memory apps hold, purgeable pages included.
        let internalPages: UInt64
        /// File-backed pages the system keeps as cache.
        let external: UInt64
    }

    /// The kernel's memory-pressure level, as `kern.memorystatus_vm_pressure_level` reports it.
    enum Pressure: Int, Sendable, Equatable, Comparable {
        case normal = 1
        case warning = 2
        case critical = 4

        init(kernelLevel: Int) {
            switch kernelLevel {
            case 4...: self = .critical
            case 2...: self = .warning
            default: self = .normal
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .normal: "Normal"
            case .warning: "Warning"
            case .critical: "Critical"
            }
        }
    }

    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let free: UInt64
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: Pressure = .normal

    /// App + wired + compressed, which is what Activity Monitor calls "Memory Used".
    var used: UInt64 { min(app + wired + compressed, total) }

    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    init(pages: Pages, pageSize: UInt64, total: UInt64) {
        self.total = total
        app = (pages.internalPages - min(pages.purgeable, pages.internalPages)) * pageSize
        wired = pages.wired * pageSize
        compressed = pages.compressed * pageSize
        cached = (pages.external + pages.purgeable) * pageSize
        let accounted = min(app + wired + compressed + cached, total)
        free = min(pages.free * pageSize, total - accounted)
    }
}
