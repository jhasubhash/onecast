import CoreLocation
import Foundation
import MapKit

/// A one-shot fix of where this Mac is; the When In Use prompt comes with the first `locate()`.
@MainActor
final class PersonalLocationProvider {
    private struct Fix: Sendable {
        let latitude: Double
        let longitude: Double
    }

    private static let fixTimeout: Duration = .seconds(15)
    /// The user has to answer a system prompt; this is how long a refresh waits for them.
    private static let promptPatience: Duration = .seconds(120)
    private static let promptPoll: Duration = .milliseconds(250)
    private static let nameTimeout: Duration = .seconds(8)
    /// The label when reverse geocoding yields no city; the weather itself is unaffected.
    private static let fallbackName = "Current location"

    /// Held for the provider's life: the system prompt belongs to this manager.
    private let manager = CLLocationManager()

    func locate() async -> Result<PersonalWeatherPlace, PersonalWeatherFailure> {
        if let failure = await authorization() { return .failure(failure) }
        switch await Self.fix(timeout: Self.fixTimeout) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let fix):
            return .success(await place(at: fix))
        }
    }

    // MARK: Authorization

    /// Nil when location may be read; otherwise the reason it may not.
    private func authorization() async -> PersonalWeatherFailure? {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            let deadline = ContinuousClock.now + Self.promptPatience
            while manager.authorizationStatus == .notDetermined {
                guard ContinuousClock.now < deadline,
                    (try? await Task.sleep(for: Self.promptPoll)) != nil
                else { return .locationTimedOut }
            }
        }
        switch manager.authorizationStatus {
        case .denied: return .locationDenied
        case .restricted: return .locationRestricted
        default: return nil
        }
    }

    // MARK: The fix

    /// Races the first position against a deadline; cancelling the stream stops location updates.
    private nonisolated static func fix(
        timeout: Duration
    ) async -> Result<Fix, PersonalWeatherFailure> {
        await withTaskGroup(of: Result<Fix, PersonalWeatherFailure>.self) { group in
            group.addTask { await firstFix() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .failure(.locationTimedOut)
            }
            let first = await group.next() ?? .failure(.locationTimedOut)
            group.cancelAll()
            return first
        }
    }

    private nonisolated static func firstFix() async -> Result<Fix, PersonalWeatherFailure> {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location, location.horizontalAccuracy >= 0 {
                    return .success(
                        Fix(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude))
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    return .failure(.locationDenied)
                }
                if update.authorizationRestricted { return .failure(.locationRestricted) }
            }
        } catch {
            return .failure(.locationUnavailable)
        }
        return .failure(.locationUnavailable)
    }

    // MARK: The name

    private func place(at fix: Fix) async -> PersonalWeatherPlace {
        let names = await cityAndCountry(at: fix)
        return PersonalWeatherPlace(
            name: names?.city ?? Self.fallbackName, country: names?.country,
            latitude: fix.latitude, longitude: fix.longitude)
    }

    /// MapKit's reverse geocoder (CLGeocoder is deprecated); nil leaves the fallback label.
    private func cityAndCountry(at fix: Fix) async -> (city: String, country: String?)? {
        let location = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let watchdog = Task {
            try? await Task.sleep(for: Self.nameTimeout)
            request.cancel()
        }
        defer { watchdog.cancel() }
        guard let items = try? await request.mapItems,
            let representations = items.first?.addressRepresentations,
            let city = representations.cityName, !city.isEmpty
        else { return nil }
        return (city, representations.regionName.flatMap { $0.isEmpty ? nil : $0 })
    }
}
