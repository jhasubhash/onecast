import Foundation

/// Why a weather refresh produced nothing, with the words the popover shows for it.
enum PersonalWeatherFailure: Error, Sendable, Equatable {
    /// Where the user can fix it, when there is somewhere to send them.
    enum Remedy: Sendable, Equatable {
        case widgetSettings
        case locationPrivacy
    }

    case noCity
    case cityNotFound(String)
    case network
    case service(Int)
    case malformed
    case locationDenied
    case locationRestricted
    case locationUnavailable
    case locationTimedOut

    var message: String {
        switch self {
        case .noCity:
            "No city is set. Enter one in this widget's settings, or turn on Use current location."
        case .cityNotFound(let query):
            "Couldn't find “\(query)”. Try the city alone, or add a country like “Paris, FR”."
        case .network:
            "Couldn't reach the weather service. Check your connection."
        case .service(let status):
            "The weather service answered with an error (HTTP \(status))."
        case .malformed:
            "The weather service sent a response Onecast couldn't read."
        case .locationDenied:
            "Location access is off for Onecast. Allow it in Privacy & Security › Location Services."
        case .locationRestricted:
            "Location access is restricted on this Mac, so Use current location can't work."
        case .locationUnavailable:
            "Your location isn't available right now."
        case .locationTimedOut:
            "Finding your location took too long."
        }
    }

    var remedy: Remedy? {
        switch self {
        case .noCity, .cityNotFound: .widgetSettings
        case .locationDenied: .locationPrivacy
        default: nil
        }
    }

    /// Whether asking again can change the answer; an unset city needs a setting, not a retry.
    var offersRetry: Bool { self != .noCity }
}
