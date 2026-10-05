import Foundation

/// The macOS Dock's `persistent-apps` as `NativeDockTile`s and back. A tile's own dictionary is
/// kept as a binary plist, so a tile this model does not understand is written back untouched.
enum NativeDockPlist {
    /// The outcome of readying tiles for a write: what to store, and what could not be.
    struct Resolution {
        var dictionaries: [[String: Any]] = []
        /// Display names of apps gone from both their saved path and their bundle ID.
        var missingApps: [String] = []
        /// Tile types with no stored dictionary to write back.
        var unwritable: [String] = []
    }

    private static let typeKey = "tile-type"
    private static let dataKey = "tile-data"
    private static let fileDataKey = "file-data"
    private static let urlStringKey = "_CFURLString"
    private static let urlStringTypeKey = "_CFURLStringType"
    private static let urlStringTypeURL = 15
    private static let appFileType = 41
    private static let fileScheme = "file://"

    // MARK: - Reading

    /// Nil when the preference holds something other than an array of tile dictionaries.
    static func tiles(fromPreference value: Any?) -> [NativeDockTile]? {
        guard let value else { return [] }
        guard let dictionaries = value as? [[String: Any]] else { return nil }
        return dictionaries.map(tile(from:))
    }

    static func tile(from dictionary: [String: Any]) -> NativeDockTile {
        let raw = try? PropertyListSerialization.data(
            fromPropertyList: dictionary, format: .binary, options: 0)
        return NativeDockTile(kind: kind(of: dictionary), raw: raw)
    }

    /// A file tile with neither a path nor a bundle ID names nothing to launch, so it stays opaque.
    private static func kind(of dictionary: [String: Any]) -> NativeDockTile.Kind {
        let type = dictionary[typeKey] as? String ?? ""
        let data = dictionary[dataKey] as? [String: Any] ?? [:]
        switch type {
        case "spacer-tile":
            return .spacer(.regular)
        case "small-spacer-tile":
            return .spacer(.small)
        case "file-tile":
            let bundleID = nonEmpty(data["bundle-identifier"] as? String)
            let path = path(of: data[fileDataKey] as? [String: Any])
            guard bundleID != nil || !path.isEmpty else { return .other(type: type) }
            let label =
                nonEmpty(data["file-label"] as? String)
                ?? nonEmpty(appName(atPath: path)) ?? bundleID ?? ""
            return .app(bundleID: bundleID, path: path, label: label)
        default:
            return .other(type: type.isEmpty ? "unknown" : type)
        }
    }

    /// A stable fingerprint of what the Dock shows, blind to the churn the Dock adds on restart.
    static func signature(of tiles: [NativeDockTile]) -> [String] {
        tiles.map { tile in
            switch tile.kind {
            case .app(let bundleID, let path, _): "app:" + (path.isEmpty ? bundleID ?? "" : path)
            case .spacer(let size): "spacer:" + size.rawValue
            case .other(let type): "other:" + type
            }
        }
    }

    // MARK: - Writing

    /// A tile's stored dictionary wins; an app or spacer authored in Onecast is synthesized.
    static func dictionary(for tile: NativeDockTile) -> [String: Any]? {
        if let raw = tile.raw, let stored = decode(raw), agrees(kind(of: stored), with: tile.kind) {
            return stored
        }
        switch tile.kind {
        case .app(let bundleID, let path, let label):
            return appDictionary(bundleID: bundleID, path: path, label: label)
        case .spacer(let size):
            let type = size == .small ? "small-spacer-tile" : "spacer-tile"
            return [typeKey: type, dataKey: [String: Any]()]
        case .other:
            return nil
        }
    }

    /// An app that moved is re-pointed at `locate`'s answer, or the Dock draws a question mark.
    static func resolve(
        _ tiles: [NativeDockTile], locate: (_ bundleID: String?, _ path: String) -> String?
    ) -> Resolution {
        var resolution = Resolution()
        for tile in tiles {
            guard var dictionary = dictionary(for: tile) else {
                if case .other(let type) = tile.kind { resolution.unwritable.append(type) }
                continue
            }
            if case .app(let bundleID, let path, let label) = tile.kind {
                guard let current = locate(bundleID, path) else {
                    let name = displayName(label: label, bundleID: bundleID, path: path)
                    if !resolution.missingApps.contains(name) {
                        resolution.missingApps.append(name)
                    }
                    continue
                }
                if current != path { relocate(&dictionary, to: current) }
            }
            resolution.dictionaries.append(dictionary)
        }
        return resolution
    }

    private static func agrees(
        _ stored: NativeDockTile.Kind, with kind: NativeDockTile.Kind
    ) -> Bool {
        switch (stored, kind) {
        case (.app, .app), (.other, .other): true
        case (.spacer(let storedSize), .spacer(let size)): storedSize == size
        default: false
        }
    }

    private static func appDictionary(
        bundleID: String?, path: String, label: String
    ) -> [String: Any] {
        var data: [String: Any] = [
            "file-label": label,
            "file-type": appFileType,
            fileDataKey: fileData(forPath: path)
        ]
        if let bundleID { data["bundle-identifier"] = bundleID }
        return [typeKey: "file-tile", dataKey: data]
    }

    private static func relocate(_ dictionary: inout [String: Any], to path: String) {
        var data = dictionary[dataKey] as? [String: Any] ?? [:]
        data[fileDataKey] = fileData(forPath: path)
        dictionary[dataKey] = data
    }

    private static func fileData(forPath path: String) -> [String: Any] {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        return [urlStringKey: url.absoluteString, urlStringTypeKey: urlStringTypeURL]
    }

    private static func decode(_ raw: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil)
            as? [String: Any]
    }

    // MARK: - Names and paths

    /// Type 15 is a `file://` URL, type 0 a POSIX path; the result never ends in a slash.
    private static func path(of fileData: [String: Any]?) -> String {
        guard let string = fileData?[urlStringKey] as? String, !string.isEmpty else { return "" }
        let path = string.hasPrefix(fileScheme) ? URL(string: string)?.path ?? "" : string
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    private static func appName(atPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        return URL(filePath: path).deletingPathExtension().lastPathComponent
    }

    private static func displayName(label: String, bundleID: String?, path: String) -> String {
        nonEmpty(label) ?? nonEmpty(appName(atPath: path)) ?? bundleID ?? "Unknown app"
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }
}
