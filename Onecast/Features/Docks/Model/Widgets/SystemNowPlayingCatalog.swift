import Foundation

/// Apple's public catalog search: a streamed Music track reports no artworks to Apple Events.
enum SystemNowPlayingCatalog {
    /// The catalog's thumbnails are templated by size; the tile never draws above this.
    static let artworkSide = 600
    private static let thumbnailSize = "100x100bb"
    private static let resultLimit = 10

    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
    }

    /// `region` is the storefront to search, so a regional release is found where it was bought.
    static func searchURL(title: String, artist: String, region: String?) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        var items = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(resultLimit)),
        ]
        if let region, !region.isEmpty { items.append(URLQueryItem(name: "country", value: region)) }
        components?.queryItems = items
        return components?.url
    }

    /// The best-matching result's cover at `artworkSide`; nil when nothing names the track or artist.
    static func artworkURL(
        in data: Data, title: String, artist: String, album: String
    ) -> URL? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let ranked = response.results.compactMap { result -> (score: Int, artwork: String)? in
            guard let artwork = result.artworkUrl100 else { return nil }
            let score =
                (same(result.trackName, title) ? 4 : 0) + (same(result.collectionName, album) ? 2 : 0)
                + (same(result.artistName, artist) ? 1 : 0)
            return score > 0 ? (score, artwork) : nil
        }
        guard let top = ranked.map(\.score).max(),
            let best = ranked.first(where: { $0.score == top })
        else { return nil }
        let sized = best.artwork.replacingOccurrences(
            of: thumbnailSize, with: "\(artworkSide)x\(artworkSide)bb")
        guard let url = URL(string: sized), url.scheme == "https" else { return nil }
        return url
    }

    private static func same(_ value: String?, _ other: String) -> Bool {
        guard let value, !other.isEmpty else { return false }
        return value.compare(other, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
