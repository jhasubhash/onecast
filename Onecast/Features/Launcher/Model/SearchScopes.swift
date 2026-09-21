import Foundation

/// The launcher's scope paths, as pure arithmetic; the filesystem walk lives in `AppBundleScanner`.
enum SearchScopes {
    /// Seeded on a fresh install; order matters, the scan deduping by bundle ID.
    static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        // Cryptex-delivered system apps; the `/Applications` Safari is a hidden symlink.
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        // The one user-facing app in CoreServices, so the directory itself is no default.
        "/System/Library/CoreServices/Finder.app",
        "~/Applications"
    ]

    /// Tilde-abbreviated and unslashed, so a settings backup stays portable across machines.
    static func abbreviate(_ path: String, homeDirectory: URL) -> String {
        let trimmed = trimTrailingSlash(path)
        let home = trimTrailingSlash(homeDirectory.path)
        if trimmed == home { return "~" }
        guard trimmed.hasPrefix(home + "/") else { return trimmed }
        return "~" + trimmed.dropFirst(home.count)
    }

    static func expand(_ path: String, homeDirectory: URL) -> String {
        let trimmed = trimTrailingSlash(path)
        guard trimmed.hasPrefix("~") else { return trimmed }
        let home = trimTrailingSlash(homeDirectory.path)
        let relative = trimmed.dropFirst().trimmingPrefix("/")
        return relative.isEmpty ? home : home + "/" + relative
    }

    /// Abbreviates every path and drops duplicates, preserving order.
    static func normalize(_ paths: [String], homeDirectory: URL) -> [String] {
        var seen = Set<String>()
        return paths
            .map { abbreviate($0, homeDirectory: homeDirectory) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
