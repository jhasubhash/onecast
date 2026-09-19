import CryptoKit
import Foundation

/// The on-disk descriptor that lets a plugin's launcher row exist before its code is built. Mirrors
/// the `PluginMetadata` the code reports; the row uses this, the session uses the compiled code.
struct PluginManifest: Codable, Sendable, Hashable {
    let name: String
    let identifier: String
    var subtitle: String?
    var icon: String?
    /// The Swift `-module-name` to compile under. Absent: derived from `name`, which is all a plugin
    /// needs, since the loader entry point is `@_cdecl` and module-independent.
    var module: String?
}

/// An installed plugin: its manifest, where its sources live, and a cheap fingerprint of those
/// sources so a rebuild fires exactly when one of them changes.
struct PluginInstall: Sendable, Hashable, Identifiable {
    let manifest: PluginManifest
    let directory: URL
    /// Every `.swift` under the plugin's folder, sorted, the builder compiles as one module.
    let sources: [URL]
    /// A hash of each source's path, size and mtime — the builder's cache key.
    let sourceHash: String

    var id: String { manifest.identifier }
    /// The `AppEntry.id` a plugin is surfaced under; survives a reinstall since it keys on identity.
    var entryID: String { "plugin:\(manifest.identifier)" }
    /// The compile module name: the manifest's, else `name` reduced to a valid Swift identifier.
    var moduleName: String { manifest.module ?? PluginInstall.moduleName(from: manifest.name) }

    /// The identifier a `plugin:` entry id carries, or nil when the id isn't a plugin's.
    static func identifier(fromEntryID entryID: String) -> String? {
        let prefix = "plugin:"
        guard entryID.hasPrefix(prefix) else { return nil }
        return String(entryID.dropFirst(prefix.count))
    }

    /// Reduces a display name to a legal Swift module name: alphanumerics only, never digit-first.
    static func moduleName(from name: String) -> String {
        let cleaned = String(name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        guard let first = cleaned.first, !first.isNumber else { return "Plugin" + cleaned }
        return cleaned
    }
}

/// Finds installed plugins under the per-channel support directory: one folder each, with a
/// `manifest.json` and the Swift sources the app compiles on demand.
enum PluginCatalog {
    static func pluginsDirectory() -> URL {
        let url = AppPaths.applicationSupport().appendingPathComponent("plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A directory without a readable `manifest.json` or without a single `.swift` source is skipped,
    /// not an error: a half-copied install simply doesn't appear.
    nonisolated static func scan(root: URL = PluginCatalog.pluginsDirectory()) -> [PluginInstall] {
        let dirs =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        return
            dirs
            .compactMap(plugin(at:))
            .sorted {
                $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending
            }
    }

    /// One directory read as a plugin, or nil when it lacks a readable `manifest.json` or any `.swift`
    /// source — the same rule `scan` applies per folder, exposed so an import can validate one first.
    nonisolated static func plugin(at dir: URL) -> PluginInstall? {
        guard
            (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
            let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
            let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else { return nil }
        let sources = swiftSources(in: dir)
        guard !sources.isEmpty else { return nil }
        return PluginInstall(
            manifest: manifest, directory: dir,
            sources: sources, sourceHash: fingerprint(of: sources, base: dir))
    }

    /// Every `.swift` under the plugin folder, sorted for a stable module order. `build`/`.build`
    /// holds the compiler's own output and is never a source.
    private static func swiftSources(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard
            let walker = fm.enumerator(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name == "build" || name == ".build" { walker.skipDescendants(); continue }
            if url.pathExtension == "swift" { found.append(url) }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// A cheap change token: each source's path relative to the plugin, its byte size and its mtime.
    /// A content edit bumps the mtime, an added or removed file changes the set — either reshapes it.
    private static func fingerprint(of sources: [URL], base: URL) -> String {
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        let lines = sources.map { url -> String in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let mtime = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            let rel = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
            return "\(rel)|\(size)|\(mtime)"
        }
        let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
