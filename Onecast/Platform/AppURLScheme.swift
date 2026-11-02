import Foundation

/// This channel's own link scheme: `onecast`, or `onecast-dev` for Debug. Set in project.yml.
enum AppURLScheme {
    static let current: String = {
        guard let scheme = Bundle.main.object(forInfoDictionaryKey: "OnecastURLScheme") as? String
        else { preconditionFailure("Info.plist must name OnecastURLScheme") }
        return scheme
    }()
}
