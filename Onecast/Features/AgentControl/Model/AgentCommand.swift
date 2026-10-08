import Foundation

/// Every request the agent channel accepts. The list is closed: a new need is a new case.
enum AgentCommand: Equatable, Sendable {
    case ping
    case state(includeContent: Bool, includeElements: Bool, pruned: Bool)
    case show(mode: String, query: String?)
    case hide
    case setQuery(String)
    /// Each chord pressed `count` times, in order, into `window` (the key window when nil).
    case key([String], count: Int, window: String?)
    case type(String, window: String?)
    case select(Int)
    case activate(Int?)
    case popToRoot
    case closeScreen
    case openSettings(tab: String?)
    case openURL(String)
    case entries(query: String?, kind: String?, limit: Int)
    case runEntry(String)
    case setAppearance(String)
    /// Presses the first element whose identifier, label or title matches.
    case press(String, window: String?)
    case waitFor
    case logs(AgentLogQuery)
    /// A PNG of one window, written to `path` or a temporary file.
    case capture(window: String, path: String?)
    /// The running Raycast extension's state and render tree, as the extension feature reports it.
    case extensionState
    case plugins

    enum DecodeError: Error, Equatable, LocalizedError {
        case unknownAction(String)
        case missing(String)
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .unknownAction(let action): return "Unknown action \"\(action)\"."
            case .missing(let field): return "Missing \"\(field)\"."
            case .invalid(let detail): return detail
            }
        }
    }

    static func decode(_ arguments: Arguments) throws -> AgentCommand {
        let action: String = try arguments.required("action")
        switch action {
        case "ping": return .ping
        case "state":
            return .state(
                includeContent: try arguments.optional("includeContent") ?? false,
                includeElements: try arguments.optional("includeElements") ?? true,
                pruned: try arguments.optional("pruned") ?? true)
        case "show":
            return .show(
                mode: try arguments.optional("mode") ?? "launcher",
                query: try arguments.optional("query"))
        case "hide": return .hide
        case "setQuery": return .setQuery(try arguments.required("text"))
        case "key":
            let keys: [String] =
                if let many: [String] = try arguments.optional("keys") { many } else {
                    [try arguments.required("key")]
                }
            let count: Int = try arguments.optional("count") ?? 1
            guard (1...200).contains(count) else {
                throw DecodeError.invalid("\"count\" must be 1 to 200.")
            }
            return .key(keys, count: count, window: try arguments.optional("window"))
        case "type":
            return .type(try arguments.required("text"), window: try arguments.optional("window"))
        case "select": return .select(try arguments.required("index"))
        case "activate": return .activate(try arguments.optional("index"))
        case "popToRoot": return .popToRoot
        case "closeScreen": return .closeScreen
        case "openSettings": return .openSettings(tab: try arguments.optional("tab"))
        case "openURL": return .openURL(try arguments.required("url"))
        case "entries":
            return .entries(
                query: try arguments.optional("query"), kind: try arguments.optional("kind"),
                limit: try arguments.optional("limit") ?? 50)
        case "runEntry": return .runEntry(try arguments.required("id"))
        case "setAppearance": return .setAppearance(try arguments.required("appearance"))
        case "press":
            return .press(try arguments.required("match"), window: try arguments.optional("window"))
        case "waitFor": return .waitFor
        case "logs": return .logs(try AgentLogQuery(arguments))
        case "extension": return .extensionState
        case "plugins": return .plugins
        case "capture":
            return .capture(
                window: try arguments.optional("window") ?? "palette",
                path: try arguments.optional("path"))
        default:
            throw DecodeError.unknownAction(action)
        }
    }

    /// Typed reads over one JSON object, naming the field a malformed request got wrong.
    struct Arguments {
        let fields: [String: Any]

        func optional<T>(_ name: String) throws -> T? {
            guard let raw = fields[name], !(raw is NSNull) else { return nil }
            let value: Any? =
                if let number = raw as? NSNumber {
                    if Self.isBool(number) {
                        T.self == Bool.self ? number.boolValue : nil
                    } else if T.self == Int.self {
                        number.intValue
                    } else {
                        T.self == Double.self ? number.doubleValue : nil
                    }
                } else {
                    raw
                }
            guard let typed = value as? T else {
                throw DecodeError.invalid("\"\(name)\" has the wrong type.")
            }
            return typed
        }

        func required<T>(_ name: String) throws -> T {
            guard let value: T = try optional(name) else { throw DecodeError.missing(name) }
            return value
        }

        private static func isBool(_ number: NSNumber) -> Bool {
            CFGetTypeID(number) == CFBooleanGetTypeID()
        }
    }
}
