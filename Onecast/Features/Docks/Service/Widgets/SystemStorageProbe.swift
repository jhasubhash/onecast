import Foundation

/// The disk reads behind System Activity's storage tab; read-only, and safe off the main actor.
enum SystemStorageProbe {
    enum ScanEvent: Sendable {
        /// A top-level item whose size is being measured.
        case began(String)
        case measured(SystemStorage.Entry)
    }

    private static let volumeKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsLocalKey,
    ]

    private static let entryKeys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey,
    ]

    /// Local, user-visible volumes only: a network share can stall a capacity query for minutes.
    static func volumes() -> [SystemStorage.Volume] {
        let urls =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: volumeKeys, options: [.skipHiddenVolumes]) ?? []
        let volumes = urls.compactMap { url -> SystemStorage.Volume? in
            guard let values = try? url.resourceValues(forKeys: Set(volumeKeys)),
                values.volumeIsLocal == true, let total = values.volumeTotalCapacity, total > 0
            else { return nil }
            let available =
                values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            return SystemStorage.Volume(
                name: values.volumeName ?? url.lastPathComponent, path: url.path,
                total: UInt64(total), available: UInt64(max(available, 0)), isRoot: url.path == "/")
        }
        return SystemStorage.ordered(volumes)
    }

    /// Sizes `root`'s top-level items one at a time; cancelling the stream stops the walk.
    static func scan(root: URL) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .utility) {
                for child in children(of: root) {
                    if Task.isCancelled { break }
                    continuation.yield(.began(child.lastPathComponent))
                    if let entry = measure(child) { continuation.yield(.measured(entry)) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private static func children(of root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Allocated bytes under `url`, symlinks left unfollowed; nil for a link or a cancelled walk.
    private static func measure(_ url: URL) -> SystemStorage.Entry? {
        guard let values = try? url.resourceValues(forKeys: entryKeys),
            values.isSymbolicLink != true
        else { return nil }
        let isDirectory = values.isDirectory == true
        guard isDirectory else {
            let bytes = UInt64(max(values.totalFileAllocatedSize ?? 0, 0))
            return SystemStorage.Entry(
                name: url.lastPathComponent, path: url.path, bytes: bytes, isDirectory: false)
        }
        guard
            let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: Array(entryKeys), options: [],
                errorHandler: { _, _ in true })
        else { return nil }
        var bytes: UInt64 = 0
        while let item = walker.nextObject() as? URL {
            if Task.isCancelled { return nil }
            guard let itemValues = try? item.resourceValues(forKeys: entryKeys),
                itemValues.isDirectory != true, itemValues.isSymbolicLink != true
            else { continue }
            bytes += UInt64(max(itemValues.totalFileAllocatedSize ?? 0, 0))
        }
        return SystemStorage.Entry(
            name: url.lastPathComponent, path: url.path, bytes: bytes, isDirectory: true)
    }
}
