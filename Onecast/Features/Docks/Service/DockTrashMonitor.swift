import AppKit

/// Whether the Trash holds anything, so the dock's Trash tile can show it full.
///
/// `~/.Trash` is protected: without Full Disk Access it can be neither watched nor listed, but it
/// can still be `stat`ed, so the count comes from its link count and is polled when unwatchable.
@MainActor
@Observable
final class DockTrashMonitor {
    private(set) var hasItems = false
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

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
        pollTask?.cancel()
    }

    private func arm() {
        let descriptor = Darwin.open(Self.url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            poll()
            return
        }
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

    private func poll() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
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

    /// APFS gives a folder one link per entry plus two; Finder's own `.DS_Store` is not an item.
    nonisolated private static func containsItems() -> Bool {
        var trash = stat(), finderFile = stat()
        guard stat(url.path, &trash) == 0 else { return false }
        let hidden = stat(url.appendingPathComponent(".DS_Store").path, &finderFile) == 0 ? 1 : 0
        return Int(trash.st_nlink) - 2 - hidden > 0
    }
}
