import Foundation
import OnecastPluginKit

/// One Weather instance's live state, and the loop that keeps it current while the tile shows.
@MainActor
@Observable
final class WeatherModel {
    struct Snapshot: Sendable {
        let source: PersonalWeatherSettings.Source
        let place: PersonalWeatherPlace
        let forecast: PersonalWeatherForecast
        let fetchedAt: Date
    }

    private typealias Load = Task<Result<Snapshot, PersonalWeatherFailure>, Never>

    /// The last good reading; kept, and dimmed by the views, while a later attempt fails.
    private(set) var snapshot: Snapshot?
    private(set) var failure: PersonalWeatherFailure?
    private(set) var isRefreshing = false
    /// Bumped when a setting changes, so views reading `settings(for:)` render again.
    private var settingsRevision = 0

    /// How long a city field must sit still before it is geocoded; it writes on every keystroke.
    private static let typingPause: Duration = .seconds(1)

    @ObservationIgnored private var seenSettings: PersonalWeatherSettings?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var lastSource: PersonalWeatherSettings.Source?
    @ObservationIgnored private var retrying = false
    @ObservationIgnored private var forced = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var refreshTask: Load?
    @ObservationIgnored private var sleeper: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var locationProvider: PersonalLocationProvider?

    /// The instance's settings now; reading it in a view body subscribes the view to changes.
    func settings(for context: DockWidgetContext) -> PersonalWeatherSettings {
        _ = settingsRevision
        return Self.read(context.preferences)
    }

    /// Runs for as long as the tile is on screen: refresh when due, sleep until the next one.
    func run(context: DockWidgetContext) async {
        let preferences = context.preferences
        seenSettings = Self.read(preferences)
        let watcher = Task { await watchSettings(preferences) }
        defer { watcher.cancel() }
        while !Task.isCancelled, !stopped {
            let source = Self.read(preferences).source
            if let wait = secondsUntilNextAttempt(for: source) {
                await sleep(seconds: wait)
            } else {
                await attempt(source: source, preferences: preferences)
            }
        }
    }

    /// "Try again": drops whatever is in flight and asks the service afresh.
    func retry() {
        requestAttempt()
    }

    func stop() {
        stopped = true
        debounce?.cancel()
        refreshTask?.cancel()
        sleeper?.cancel()
    }

    // MARK: Settings

    private static func read(_ preferences: DockWidgetPreferences) -> PersonalWeatherSettings {
        PersonalWeatherSettings(string: preferences.string, bool: preferences.bool)
    }

    /// Re-renders on any setting change, and refetches only when the weather's source changed.
    private func watchSettings(_ preferences: DockWidgetPreferences) async {
        for await _ in PersonalDefaults.changes() {
            let new = Self.read(preferences)
            guard new != seenSettings else { continue }
            let sourceChanged = new.source != seenSettings?.source
            seenSettings = new
            settingsRevision &+= 1
            guard sourceChanged else { continue }
            debounce?.cancel()
            guard case .city = new.source else {
                requestAttempt()
                continue
            }
            debounce = Task { [weak self] in
                guard (try? await Task.sleep(for: Self.typingPause)) != nil else { return }
                self?.requestAttempt()
            }
        }
    }

    // MARK: Refreshing

    private func requestAttempt() {
        forced = true
        refreshTask?.cancel()
        sleeper?.cancel()
    }

    /// Nil when an attempt is due now.
    private func secondsUntilNextAttempt(for source: PersonalWeatherSettings.Source) -> TimeInterval? {
        guard !forced, let lastAttempt, lastSource == source else { return nil }
        let due = PersonalWeatherSchedule.nextAttempt(after: lastAttempt, retrying: retrying)
        let remaining = due.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    private func sleep(seconds: TimeInterval) async {
        let task = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(seconds)) }
        sleeper = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func attempt(
        source: PersonalWeatherSettings.Source, preferences: DockWidgetPreferences
    ) async {
        forced = false
        if lastSource != source {
            snapshot = nil
            failure = nil
        }
        lastSource = source
        isRefreshing = true
        let task = Task { await load(source: source, preferences: preferences) }
        refreshTask = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        isRefreshing = false
        // A cancelled load is a superseded or abandoned one; its result is not an answer.
        guard !task.isCancelled, !Task.isCancelled else { return }
        lastAttempt = Date()
        switch result {
        case .success(let fresh):
            snapshot = fresh
            failure = nil
            retrying = false
        case .failure(let reason):
            failure = reason
            retrying = reason.offersRetry
        }
    }

    private func load(
        source: PersonalWeatherSettings.Source, preferences: DockWidgetPreferences
    ) async -> Result<Snapshot, PersonalWeatherFailure> {
        let place: PersonalWeatherPlace
        switch await resolve(source, preferences: preferences) {
        case .success(let resolved): place = resolved
        case .failure(let reason): return .failure(reason)
        }
        do {
            let forecast = try await PersonalWeatherService.forecast(
                latitude: place.latitude, longitude: place.longitude)
            return .success(
                Snapshot(source: source, place: place, forecast: forecast, fetchedAt: Date()))
        } catch {
            return .failure(error)
        }
    }

    private func resolve(
        _ source: PersonalWeatherSettings.Source, preferences: DockWidgetPreferences
    ) async -> Result<PersonalWeatherPlace, PersonalWeatherFailure> {
        switch source {
        case .unset:
            return .failure(.noCity)
        case .current:
            let provider = locationProvider ?? PersonalLocationProvider()
            locationProvider = provider
            return await provider.locate()
        case .city(let query):
            let stored = preferences.string(PersonalWeatherPlaceCache.preferenceKey)
            if let cached = PersonalWeatherPlaceCache.decode(stored, for: query) {
                return .success(cached)
            }
            do {
                let place = try await PersonalWeatherService.place(
                    for: query, language: Locale.current.language.languageCode?.identifier)
                preferences.set(
                    PersonalWeatherPlaceCache.encode(place, for: query),
                    for: PersonalWeatherPlaceCache.preferenceKey)
                return .success(place)
            } catch {
                return .failure(error)
            }
        }
    }
}
