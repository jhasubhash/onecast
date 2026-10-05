import Foundation

/// Volume capacity and the folder-size scan: what a volume holds and what fills it.
enum SystemStorage {
    struct Volume: Sendable, Equatable, Identifiable {
        let name: String
        let path: String
        let total: UInt64
        /// What the user can still use, purgeable space included, as Finder counts it.
        let available: UInt64
        let isRoot: Bool

        var id: String { path }
        var used: UInt64 { total - min(available, total) }
        var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    }

    struct Entry: Sendable, Equatable, Identifiable {
        let name: String
        let path: String
        let bytes: UInt64
        let isDirectory: Bool

        var id: String { path }
    }

    /// A folder whose top-level children the scan sizes.
    enum ScanRoot: String, Sendable, CaseIterable, Identifiable {
        case home, applications, library

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .applications: "Applications"
            case .library: "Library"
            }
        }

        var symbol: String {
            switch self {
            case .home: "house"
            case .applications: "square.grid.2x2"
            case .library: "books.vertical"
            }
        }

        func url(home: URL) -> URL {
            switch self {
            case .home: home
            case .applications: URL(fileURLWithPath: "/Applications", isDirectory: true)
            case .library: home.appending(path: "Library", directoryHint: .isDirectory)
            }
        }
    }

    /// The root volume first, then the rest by name.
    static func ordered(_ volumes: [Volume]) -> [Volume] {
        volumes.sorted { lhs, rhs in
            if lhs.isRoot != rhs.isRoot { return lhs.isRoot }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.path < rhs.path : order == .orderedAscending
        }
    }

    /// Largest first; equal sizes fall back to name so a rescan does not shuffle rows.
    static func ranked(_ entries: [Entry]) -> [Entry] {
        entries.sorted { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.path < rhs.path : order == .orderedAscending
        }
    }

    /// An entry's share of the scanned total, 0...1.
    static func share(of entry: Entry, in total: UInt64) -> Double {
        total == 0 ? 0 : min(Double(entry.bytes) / Double(total), 1)
    }
}
