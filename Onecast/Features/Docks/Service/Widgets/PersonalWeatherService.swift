import Foundation

/// Open-Meteo over the network; the parsing lives in `PersonalWeatherFeed`.
enum PersonalWeatherService {
    /// Cacheless, never `URLSession.shared`, so no weather lands in a shared URL cache on disk.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Off-main via `URLSession`; only the plain-value forecast crosses back.
    nonisolated static func forecast(
        latitude: Double, longitude: Double
    ) async throws(PersonalWeatherFailure) -> PersonalWeatherForecast {
        let url = PersonalWeatherFeed.forecastURL(latitude: latitude, longitude: longitude)
        let data = try await body(of: url)
        return try PersonalWeatherFeed.forecast(from: data)
    }

    /// The place `query` names; throws `.cityNotFound` when the geocoder has nothing for it.
    nonisolated static func place(
        for query: PersonalWeatherPlaceQuery, language: String?
    ) async throws(PersonalWeatherFailure) -> PersonalWeatherPlace {
        let url = PersonalWeatherFeed.geocodingURL(for: query, language: language)
        let data = try await body(of: url)
        guard let place = query.choose(from: try PersonalWeatherFeed.places(from: data)) else {
            throw .cityNotFound(query.displayText)
        }
        return place
    }

    private nonisolated static func body(of url: URL) async throws(PersonalWeatherFailure) -> Data {
        let request = URLRequest(url: url, timeoutInterval: requestTimeout)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network
        }
        guard let http = response as? HTTPURLResponse else { throw .malformed }
        guard http.statusCode == 200 else { throw .service(http.statusCode) }
        return data
    }

    private nonisolated static let requestTimeout: TimeInterval = 20
}
