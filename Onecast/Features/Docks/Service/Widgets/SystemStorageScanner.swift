import Foundation
import Observation

/// A cancellable, read-only size scan of one folder's top-level items. It never deletes anything.
@MainActor
@Observable
final class SystemStorageScanner {
    enum Phase: Equatable {
        case idle
        /// The top-level item being measured, once the walk has reached one.
        case scanning(current: String?)
        case finished
        case cancelled
    }

    private(set) var root: SystemStorage.ScanRoot?
    private(set) var entries: [SystemStorage.Entry] = []
    private(set) var phase = Phase.idle

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    isolated deinit {
        task?.cancel()
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var scannedBytes: UInt64 { entries.reduce(0) { $0 + $1.bytes } }

    func scan(_ root: SystemStorage.ScanRoot) {
        task?.cancel()
        self.root = root
        entries = []
        phase = .scanning(current: nil)
        let events = SystemStorageProbe.scan(root: root.url(home: homeDirectory))
        task = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .began(let name): phase = .scanning(current: name)
                case .measured(let entry): entries = SystemStorage.ranked(entries + [entry])
                }
            }
            guard let self, !Task.isCancelled else { return }
            phase = .finished
        }
    }

    func cancel() {
        guard isScanning else { return }
        task?.cancel()
        task = nil
        phase = .cancelled
    }
}
