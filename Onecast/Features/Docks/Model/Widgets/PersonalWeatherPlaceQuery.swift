import Foundation

/// A city typed into the widget's settings: "Cupertino", or "Paris, FR" to say which Paris.
struct PersonalWeatherPlaceQuery: Sendable, Equatable {
    /// The part before the first comma; the geocoder only matches on this.
    let name: String
    /// What follows the comma: a country code or name, or a state or province.
    let qualifier: String?
    /// Case, accent and spacing folded away, so two spellings of one city share a cache entry.
    let key: String

    /// Nil when there is no city name to look for.
    init?(_ text: String) {
        let parts = text.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let name = Self.collapsed(parts.first.map(String.init) ?? "")
        guard !name.isEmpty else { return nil }
        let qualifier = parts.count > 1 ? Self.collapsed(String(parts[1])) : ""
        self.name = name
        self.qualifier = qualifier.isEmpty ? nil : qualifier
        key = Self.fold(name) + (qualifier.isEmpty ? "" : "," + Self.fold(qualifier))
    }

    /// How many matches to ask for: one is enough until a qualifier has to pick between cities.
    var candidateCount: Int { qualifier == nil ? 1 : Self.qualifiedCandidateCount }

    /// The first candidate the qualifier names, or the first candidate when there is none.
    func choose(from candidates: [PersonalWeatherPlace]) -> PersonalWeatherPlace? {
        guard let qualifier else { return candidates.first }
        let wanted = Self.fold(qualifier)
        return candidates.first { place in
            [place.countryCode, place.country, place.admin1].contains { $0.map(Self.fold) == wanted }
        }
    }

    /// What an error message shows back to the user.
    var displayText: String {
        qualifier.map { "\(name), \($0)" } ?? name
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    private static let qualifiedCandidateCount = 50

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
