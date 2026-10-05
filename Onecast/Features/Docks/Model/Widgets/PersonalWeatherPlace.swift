import Foundation

/// A place the weather is read for: a geocoded city, or the Mac's own position.
struct PersonalWeatherPlace: Sendable, Equatable, Codable {
    let name: String
    let admin1: String?
    let country: String?
    let countryCode: String?
    let latitude: Double
    let longitude: Double

    init(
        name: String, admin1: String? = nil, country: String? = nil, countryCode: String? = nil,
        latitude: Double, longitude: Double
    ) {
        self.name = name
        self.admin1 = admin1
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The line under the name: the state or province, else the country.
    var region: String? { admin1 ?? country }

    var hasValidCoordinates: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}
