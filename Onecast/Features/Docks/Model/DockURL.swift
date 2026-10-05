import Foundation

/// A parsed `onecast://dock/…` link: what to switch, by id or by name.
enum DockURL: Equatable, Sendable {
    case setup(String)
    case toggle(String)
    case layout(dock: String, layout: String)

    static let scheme = "onecast"
    static let host = "dock"

    /// Whether the link addresses Docks at all, so a malformed one is reported rather than ignored.
    static func claims(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && segments(of: url).first?.lowercased() == host
    }

    /// Host and path unify `onecast://dock/setup/x` and `onecast:/dock/setup/x`.
    static func parse(_ url: URL) -> DockURL? {
        guard claims(url) else { return nil }
        let parts = segments(of: url).dropFirst()
        let references = parts.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let verb = parts.first?.lowercased(), !references.contains(where: \.isEmpty) else {
            return nil
        }
        switch (verb, references.count) {
        case ("setup", 1): return .setup(references[0])
        case ("toggle", 1): return .toggle(references[0])
        case ("layout", 2): return .layout(dock: references[0], layout: references[1])
        default: return nil
        }
    }

    /// A UUID wins when it names a candidate; otherwise the name matches ignoring case and accents.
    static func resolve(_ reference: String, among candidates: [(id: UUID, name: String)]) -> UUID? {
        let wanted = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: wanted), candidates.contains(where: { $0.id == id }) {
            return id
        }
        return candidates.first {
            $0.name.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }?.id
    }

    /// Split before decoding, so an encoded slash stays inside a name.
    private static func segments(of url: URL) -> [String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return []
        }
        var raw: [String] = []
        if let host = components.host, !host.isEmpty { raw.append(host) }
        raw += components.percentEncodedPath.split(separator: "/").map(String.init)
        return raw.map { $0.removingPercentEncoding ?? $0 }
    }
}
