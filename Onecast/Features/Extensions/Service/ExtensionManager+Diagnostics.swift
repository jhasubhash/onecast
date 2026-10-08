#if DEBUG
import Foundation

extension ExtensionManager {
    /// The running command as data: its state, how deep it navigated, and the tree it rendered.
    var diagnostics: [String: Any] {
        var object: [String: Any] = [
            "running": running.map { $0.entryID as Any } ?? NSNull(),
            "navigationDepth": navigationDepth,
            "installed": installed.map(\.manifest.name).sorted(),
        ]
        switch state {
        case .idle: object["state"] = "idle"
        case .launching: object["state"] = "launching"
        case .finished: object["state"] = "finished"
        case .failed(let message):
            object["state"] = "failed"
            object["failure"] = message
        case .rendered(let tree):
            object["state"] = "rendered"
            object["screens"] = tree.screens.map(\.inspection)
        }
        return object
    }
}
#endif
