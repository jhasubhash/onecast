import Foundation

/// The figure a System Activity tile leads with.
enum SystemActivityMetric: String, Sendable, CaseIterable {
    case cpu, memory, storage

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .storage: "Storage"
        }
    }

    /// Short enough to sit under a ring on a single tile.
    var shortTitle: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "RAM"
        case .storage: "DISK"
        }
    }
}
