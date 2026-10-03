import Foundation

/// A tab the browser relay reaches in the user's Chrome, as its `/json/list` reports it.
struct BrowserRelayPage: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let url: String
    let type: String

    /// The list carries workers and other targets too; only a page has a document to read or drive.
    static func pages(fromList data: Data) throws -> [BrowserRelayPage] {
        try JSONDecoder().decode([BrowserRelayPage].self, from: data).filter { $0.type == "page" }
    }

    /// An open tab on the URL's exact host, so a logged-in tab is reused rather than a blank one opened.
    static func reusable(for url: URL, in pages: [BrowserRelayPage]) -> BrowserRelayPage? {
        guard let host = url.host()?.lowercased() else { return nil }
        return pages.first { URL(string: $0.url)?.host()?.lowercased() == host }
    }

    static func listing(_ pages: [BrowserRelayPage]) -> String {
        guard !pages.isEmpty else { return "No tabs are open in the relayed Chrome." }
        return pages.map { "\($0.id) · \($0.title) · \($0.url)" }.joined(separator: "\n")
    }

    /// Caps what a page hands back, so one huge document can't flood the model's context.
    static func clipped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n… [\(text.count - limit) more characters cut]"
    }
}
