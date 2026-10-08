#if DEBUG
import Foundation

extension PluginManager {
    /// What is installed, what runs, and whether the mapped build still matches its sources.
    var diagnostics: [String: Any] {
        var object: [String: Any] = [
            "installed": installed.map {
                ["identifier": $0.id, "name": $0.displayName, "sourceHash": $0.sourceHash,
                 "directory": $0.directory.path]
            },
            "running": runningIdentifier.map { $0 as Any } ?? NSNull(),
        ]
        switch state {
        case .idle: object["state"] = "idle"
        case .loading: object["state"] = "loading"
        case .active: object["state"] = "active"
        case .failed(let message):
            object["state"] = "failed"
            object["failure"] = message
        }
        if let build = loadedBuild {
            let current = installed.first { $0.id == build.identifier }?.sourceHash
            let matches: Any = current.map { ($0 == build.sourceHash) as Any } ?? NSNull()
            object["loaded"] = [
                "identifier": build.identifier, "sourceHash": build.sourceHash, "dylib": build.dylib.path,
                "loadedAt": ISO8601DateFormatter().string(from: build.at),
                "matchesSources": matches,
            ]
        }
        return object
    }
}
#endif
