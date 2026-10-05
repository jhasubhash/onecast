import AppKit

/// Whether the Trash holds anything, so the dock's Trash tile can show it full.
///
/// `~/.Trash` is protected: without Full Disk Access the folder can neither be watched nor
/// listed, and the tile keeps showing the empty Trash.
@MainActor
@Observable
final class DockTrashMonitor {
    private(set) var hasItems = false
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    nonisolated static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    init() {
        arm()
        refresh()
    }

    isolated deinit {
        source?.cancel()
        refreshTask?.cancel()
    }

    private func arm() {
        let descriptor = Darwin.open(Self.url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .revoke],
            queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        self.source = source
        source.resume()
    }

    /// Debounced: emptying the Trash is a burst of removals.
    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .utility) { Self.containsItems() }.value
            guard let self, !Task.isCancelled, found != hasItems else { return }
            hasItems = found
        }
    }

    nonisolated private static func containsItems() -> Bool {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return !(contents ?? []).isEmpty
    }
}
