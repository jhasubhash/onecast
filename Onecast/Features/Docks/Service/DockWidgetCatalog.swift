import Foundation

/// An installed third-party DockWidget, with the fingerprint of its sources.
struct DockWidgetInstall: Sendable, Hashable, Identifiable {
    let manifest: DockWidgetManifest
    let directory: URL
    /// Every `.swift` under the widget's folder, sorted, the builder compiles as one module.
    let sources: [URL]
    /// A hash of each source's path, size and mtime — the builder's cache key.
    let sourceHash: String

    /// The manifest identifier: what a dock item's `DockWidgetReference.widgetID` stores.
    var id: String { manifest.identifier }
    /// The compile module name: the manifest's, else `name` reduced to a valid Swift identifier.
    var moduleName: String { manifest.module ?? PluginInstall.moduleName(from: manifest.name) }
}

/// Finds installed DockWidgets: one folder each, a `manifest.json` beside its Swift sources.
enum DockWidgetCatalog {
    static func widgetsDirectory() -> URL {
        let url = AppPaths.applicationSupport().appendingPathComponent("dockwidgets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A half-copied folder is skipped, not an error; of two claiming one id, the first wins.
    nonisolated static func scan(root: URL = DockWidgetCatalog.widgetsDirectory()) -> [DockWidgetInstall] {
        let dirs =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        let sorted = dirs.compactMap(widget(at:)).sorted {
            let order = $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name)
            return order == .orderedSame ? $0.directory.path < $1.directory.path : order == .orderedAscending
        }
        var seen = Set<String>()
        return sorted.filter { seen.insert($0.id).inserted }
    }

    /// A directory as a DockWidget, or nil without a usable manifest or any `.swift` source.
    nonisolated static func widget(at dir: URL) -> DockWidgetInstall? {
        guard
            (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
            let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
            let manifest = try? JSONDecoder().decode(DockWidgetManifest.self, from: data),
            manifest.hasUsableIdentifier
        else { return nil }
        let sources = PluginCatalog.swiftSources(in: dir)
        guard !sources.isEmpty else { return nil }
        return DockWidgetInstall(
            manifest: manifest, directory: dir, sources: sources,
            sourceHash: PluginCatalog.fingerprint(of: sources, base: dir))
    }
}
