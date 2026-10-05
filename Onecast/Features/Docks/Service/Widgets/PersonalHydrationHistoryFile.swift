import Foundation

/// One instance's drink history on disk: a small JSON file named for the instance id.
struct HydrationHistoryFile: Sendable {
    let url: URL

    /// Only the characters of an id are kept, so a hostile id can never step out of `directory`.
    init(directory: URL, instanceID: String) {
        let name = instanceID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        url = directory.appending(path: "\(name).json", directoryHint: .notDirectory)
    }

    /// A missing or unreadable file is an empty log.
    func load() -> HydrationLog {
        guard let data = try? Data(contentsOf: url) else { return HydrationLog() }
        return HydrationLog.decode(data)
    }

    func save(_ log: HydrationLog) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try log.encoded().write(to: url, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
