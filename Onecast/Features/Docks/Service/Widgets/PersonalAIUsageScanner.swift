import Foundation

/// What earlier scans learned about each log file, so the next one reopens only what changed.
struct PersonalAIUsageFileCache: Sendable {
    struct Stamp: Sendable, Equatable {
        let size: Int
        let modified: Date
    }

    struct Parsed: Sendable {
        let provider: PersonalAIUsageProvider
        let stamp: Stamp
        let entries: [PersonalAIUsageEntry]
    }

    fileprivate(set) var files: [String: Parsed] = [:]
}

struct PersonalAIUsageScan: Sendable {
    /// Every provider's entries, merged across its files so a copied turn counts once.
    fileprivate(set) var entries: [PersonalAIUsageProvider: [PersonalAIUsageEntry]] = [:]
    /// Providers whose log folder exists, whether or not it holds anything in range.
    fileprivate(set) var foundFolders: Set<PersonalAIUsageProvider> = []
    fileprivate(set) var cache: PersonalAIUsageFileCache
    /// Files this scan had to read; the rest came from the cache.
    fileprivate(set) var openedFiles = 0
    /// Files that could not be read; they are left out rather than failing the scan.
    fileprivate(set) var unreadableFiles = 0
    /// False when the scan was cancelled partway, so `entries` is not a full picture.
    fileprivate(set) var isComplete = true

    fileprivate init(cache: PersonalAIUsageFileCache) {
        self.cache = cache
    }
}

/// Reads the Claude Code and Codex session logs under a home directory, off the caller's thread.
enum PersonalAIUsageScanner {
    private static let chunkBytes = 1 << 20
    /// A line this long is an embedded blob, not a usage record; it is skipped unread.
    private static let maxLineBytes = 64 << 20
    private static let newline: Int32 = 0x0A

    nonisolated static func folder(for provider: PersonalAIUsageProvider, home: URL) -> URL {
        switch provider {
        case .claudeCode: home.appending(path: ".claude/projects", directoryHint: .isDirectory)
        case .codex: home.appending(path: ".codex/sessions", directoryHint: .isDirectory)
        }
    }

    /// Opens only files touched since `modifiedSince`; a log has nothing newer than its mtime.
    nonisolated static func scan(
        home: URL, modifiedSince: Date, cache: PersonalAIUsageFileCache
    ) -> PersonalAIUsageScan {
        var scan = PersonalAIUsageScan(cache: cache)
        for provider in PersonalAIUsageProvider.allCases {
            guard !Task.isCancelled else {
                scan.isComplete = false
                break
            }
            let root = folder(for: provider, home: home).resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                scan.prune(provider, keeping: [])
                scan.entries[provider] = []
                continue
            }
            scan.foundFolders.insert(provider)
            switch provider {
            case .claudeCode:
                collect(PersonalAIUsageClaudeLog.self, provider, root, modifiedSince, &scan)
            case .codex:
                collect(PersonalAIUsageCodexLog.self, provider, root, modifiedSince, &scan)
            }
        }
        return scan
    }

    nonisolated private static func collect<Log: PersonalAIUsageLogParsing>(
        _ log: Log.Type, _ provider: PersonalAIUsageProvider, _ root: URL, _ modifiedSince: Date,
        _ scan: inout PersonalAIUsageScan
    ) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true })
        else { return }

        var merged = PersonalAIUsageDeduper()
        var seen: Set<String> = []
        while let url = walker.nextObject() as? URL {
            guard !Task.isCancelled else {
                scan.isComplete = false
                break
            }
            guard url.pathExtension == "jsonl",
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true, let modified = values.contentModificationDate,
                let size = values.fileSize
            else { continue }
            let path = url.path
            seen.insert(path)
            guard modified >= modifiedSince else { continue }

            let stamp = PersonalAIUsageFileCache.Stamp(size: size, modified: modified)
            if let known = scan.cache.files[path], known.stamp == stamp {
                merged.add(contentsOf: known.entries)
            } else if let entries = parse(url, as: log) {
                scan.openedFiles += 1
                scan.cache.files[path] = PersonalAIUsageFileCache.Parsed(
                    provider: provider, stamp: stamp, entries: entries)
                merged.add(contentsOf: entries)
            } else if Task.isCancelled {
                scan.isComplete = false
                break
            } else {
                scan.cache.files[path] = nil
                scan.unreadableFiles += 1
            }
        }
        scan.entries[provider] = merged.entries
        if scan.isComplete { scan.prune(provider, keeping: seen) }
    }

    /// The entries of one file, or nil when it cannot be read (or the scan was cancelled).
    nonisolated private static func parse<Log: PersonalAIUsageLogParsing>(
        _ url: URL, as log: Log.Type
    ) -> [PersonalAIUsageEntry]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var parser = Log()
        var carried = Data()
        var isDiscarding = false
        while true {
            guard !Task.isCancelled else { return nil }
            let chunk: Data
            do {
                guard let next = try handle.read(upToCount: chunkBytes), !next.isEmpty else {
                    break
                }
                chunk = next
            } catch {
                return nil
            }
            chunk.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var start = 0
                while start < raw.count {
                    guard let hit = memchr(base + start, newline, raw.count - start) else {
                        break
                    }
                    let end = base.distance(to: UnsafeRawPointer(hit))
                    if isDiscarding {
                        isDiscarding = false
                    } else if carried.isEmpty {
                        parser.consume(Data(bytes: base + start, count: end - start))
                    } else {
                        carried.append(Data(bytes: base + start, count: end - start))
                        parser.consume(carried)
                        carried.removeAll(keepingCapacity: true)
                    }
                    start = end + 1
                }
                guard start < raw.count, !isDiscarding else { return }
                carried.append(Data(bytes: base + start, count: raw.count - start))
                if carried.count > maxLineBytes {
                    carried.removeAll()
                    isDiscarding = true
                }
            }
        }
        if !carried.isEmpty, !isDiscarding { parser.consume(carried) }
        return parser.entries
    }
}

extension PersonalAIUsageScan {
    /// Forgets cached files that no longer exist, so the cache cannot grow forever.
    fileprivate mutating func prune(_ provider: PersonalAIUsageProvider, keeping seen: Set<String>) {
        for (path, parsed) in cache.files where parsed.provider == provider && !seen.contains(path) {
            cache.files[path] = nil
        }
    }
}
