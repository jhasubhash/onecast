import Foundation

/// The filesystem walk behind `AppIndex`: the `.app`s scopes point at, kept out of `SearchScopes`.
enum AppBundleScanner {
    /// Where a bundle ships its own apps: Xcode keeps Instruments and Simulator there.
    private static let embeddedAppFolders = [
        "Contents/Applications", "Contents/Developer/Applications"
    ]

    /// Every `.app` the scopes point at. One subfolder deep; deeper nesting needs its own scope.
    static func appBundles(in scopes: [String], homeDirectory: URL) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for scope in scopes {
            let url = URL(fileURLWithPath: SearchScopes.expand(scope, homeDirectory: homeDirectory))
            if url.pathExtension == "app" {
                if fm.fileExists(atPath: url.path) { result.append(contentsOf: withEmbedded(url)) }
                continue
            }
            result.append(contentsOf: appBundles(under: url, subfolderDepth: 1))
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// An `.app` is never descended into beyond its embedded-app folders.
    private static func appBundles(under url: URL, subfolderDepth: Int) -> [URL] {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
        else { return [] }

        var result: [URL] = []
        for item in items {
            if item.pathExtension == "app" {
                result.append(contentsOf: withEmbedded(item))
            } else if subfolderDepth > 0,
                (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            {
                result.append(contentsOf: appBundles(under: item, subfolderDepth: subfolderDepth - 1))
            }
        }
        return result
    }

    private static func withEmbedded(_ app: URL) -> [URL] {
        [app]
            + embeddedAppFolders.flatMap {
                appBundles(under: app.appendingPathComponent($0), subfolderDepth: 0)
            }
    }
}
