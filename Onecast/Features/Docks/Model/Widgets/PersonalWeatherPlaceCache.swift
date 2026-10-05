import Foundation

/// The geocoded place a widget keeps in its preferences, tagged with the query it answers.
enum PersonalWeatherPlaceCache {
    /// The undeclared preference key the encoded entry lives under.
    static let preferenceKey = "resolvedLocation"

    private struct Entry: Codable {
        let key: String
        let place: PersonalWeatherPlace
    }

    static func encode(
        _ place: PersonalWeatherPlace, for query: PersonalWeatherPlaceQuery
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Entry(key: query.key, place: place)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The place cached for this very query; anything else is nil, so a new city re-geocodes.
    static func decode(
        _ stored: String?, for query: PersonalWeatherPlaceQuery
    ) -> PersonalWeatherPlace? {
        guard let data = stored?.data(using: .utf8),
            let entry = try? JSONDecoder().decode(Entry.self, from: data),
            entry.key == query.key, entry.place.hasValidCoordinates
        else { return nil }
        return entry.place
    }
}
