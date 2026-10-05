import Foundation
import Observation
import OnecastPluginKit

/// One AI Usage widget's live state: Codex's limits from the app, and token activity from logs.
@MainActor
@Observable
final class AIUsageModel {
    /// What the last finished scan found, over the range it was computed for.
    struct Activity: Equatable {
        let range: PersonalAIUsageRange
        /// Only providers with tokens in the range; one with none is left out, never shown as 0.
        let summaries: [PersonalAIUsageSummary]
        let foundFolders: Set<PersonalAIUsageProvider>
        let updatedAt: Date

        var combined: PersonalAIUsageSeries { .merged(summaries.map(\.series)) }
    }

    struct LimitRow: Identifiable, Equatable {
        let id: String
        let fallbackTitle: String
        let window: PersonalAIUsageLimitWindow
    }

    /// Why Codex's limits are or are not on screen, for the popover to explain.
    enum CodexStatus: Equatable {
        case connected
        case checking
        case turnedOff
        case notInstalled
        case signedOut
        case failed(String)
    }

    private(set) var settings = PersonalAIUsageSettings()
    private(set) var activity: Activity?
    private(set) var isScanning = false
    /// When this widget last asked the Codex manager to check, which is when limits were fetched.
    private(set) var limitsRequestedAt: Date?

    @ObservationIgnored private var fileCache = PersonalAIUsageFileCache()
    @ObservationIgnored private var wake: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var runGeneration = 0
    @ObservationIgnored private var isForcingLimits = false

    /// Codex's rate-limit windows, primary first; nil when there are none to show.
    var limits: [LimitRow]? {
        guard let rateLimits = AppCore.shared.chatGPTSubscription.rateLimits else { return nil }
        var rows: [LimitRow] = []
        if let window = rateLimits.primary {
            rows.append(Self.row("primary", "Primary", window))
        }
        if let window = rateLimits.secondary {
            rows.append(Self.row("secondary", "Secondary", window))
        }
        return rows.isEmpty ? nil : rows
    }

    var codexStatus: CodexStatus {
        let core = AppCore.shared
        guard Self.isCodexEnabled(core) else { return .turnedOff }
        switch core.chatGPTSubscription.phase {
        case .idle, .starting: return .checking
        case .signedOut: return .signedOut
        case .unavailable: return .notInstalled
        case .failed(let message): return .failed(message)
        case .connected: return .connected
        }
    }

    var codexPlan: String? { AppCore.shared.chatGPTSubscription.account?.planTitle }

    /// The newest of the last scan and the last limits check.
    var updatedAt: Date? { [activity?.updatedAt, limitsRequestedAt].compactMap { $0 }.max() }

    var isRefreshing: Bool { isScanning || AppCore.shared.chatGPTSubscription.phase == .starting }

    /// Drives the widget while its tile is on screen: scans now, on a beat, and on a new range.
    func run(_ context: DockWidgetContext) async {
        let preferences = context.preferences
        let (requests, wake) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1))
        runGeneration += 1
        let generation = runGeneration
        self.wake = wake
        adopt(Self.settings(from: preferences))

        let watcher = Task { [weak self] in
            for await _ in PersonalDefaults.changes() {
                guard let self else { return }
                if self.adopt(Self.settings(from: preferences)) { wake.yield() }
            }
        }
        let beat = Task { [weak self] in
            while !Task.isCancelled {
                let delay = PersonalAIUsageSchedule.delay(
                    now: Date(), calendar: .autoupdatingCurrent)
                try? await Task.sleep(for: .seconds(delay))
                guard self != nil, !Task.isCancelled else { return }
                wake.yield()
            }
        }
        defer {
            watcher.cancel()
            beat.cancel()
            wake.finish()
            if generation == runGeneration { self.wake = nil }
        }

        wake.yield()
        var isRestart = true
        for await _ in requests {
            refreshLimits()
            let isFresh = isRestart && hasFreshActivity
            isRestart = false
            if !isFresh { await rescan() }
        }
    }

    /// A tile that comes back on screen shows what the last scan found rather than scanning again.
    private var hasFreshActivity: Bool {
        guard let activity, activity.range == settings.range else { return false }
        let now = Date()
        return !PersonalAIUsageSchedule.isStale(since: activity.updatedAt, now: now)
            && Calendar.autoupdatingCurrent.isDate(activity.updatedAt, inSameDayAs: now)
    }

    /// The popover's Refresh and Try again: a rescan, and a Codex check even if one is recent.
    func requestRefresh() {
        isForcingLimits = true
        wake?.yield()
    }

    func didRemove() {
        wake?.finish()
        wake = nil
    }

    /// True when the change calls for a fresh scan: a new range or a different kind of content.
    @discardableResult
    private func adopt(_ next: PersonalAIUsageSettings) -> Bool {
        let rescans = next.range != settings.range || next.content != settings.content
        if next != settings { settings = next }
        return rescans
    }

    /// Never asks while a check is under way, and never touches the manager otherwise.
    private func refreshLimits() {
        let force = isForcingLimits
        isForcingLimits = false
        let core = AppCore.shared
        guard Self.isCodexEnabled(core) else { return }
        let subscription = core.chatGPTSubscription
        guard subscription.phase != .starting else { return }
        let now = Date()
        let isDue =
            force || subscription.phase == .idle
            || PersonalAIUsageSchedule.isStale(since: limitsRequestedAt, now: now)
        guard isDue else { return }
        limitsRequestedAt = now
        subscription.refresh()
    }

    private func rescan() async {
        let range = settings.range
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let since = range.interval(now: now, calendar: calendar).start
        let cache = fileCache
        let home = FileManager.default.homeDirectoryForCurrentUser
        isScanning = true
        defer { isScanning = false }

        let work = Task.detached(priority: .utility) {
            let scan = PersonalAIUsageScanner.scan(home: home, modifiedSince: since, cache: cache)
            let summaries = PersonalAIUsageProvider.allCases.compactMap { provider in
                let series = PersonalAIUsageAggregator.series(
                    entries: scan.entries[provider] ?? [], range: range, now: now,
                    calendar: calendar)
                return series.hasActivity
                    ? PersonalAIUsageSummary(provider: provider, series: series) : nil
            }
            return ScanOutcome(
                cache: scan.cache, isComplete: scan.isComplete, summaries: summaries,
                foundFolders: scan.foundFolders)
        }
        let outcome = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        fileCache = outcome.cache
        guard outcome.isComplete, range == settings.range else { return }
        activity = Activity(
            range: range, summaries: outcome.summaries, foundFolders: outcome.foundFolders,
            updatedAt: Date())
    }

    private static func row(
        _ id: String, _ fallback: String, _ window: ChatGPTSubscription.UsageWindow
    ) -> LimitRow {
        LimitRow(
            id: id, fallbackTitle: fallback,
            window: PersonalAIUsageLimitWindow(
                usedPercent: window.usedPercent, durationMinutes: window.durationMinutes,
                resetsAt: window.resetsAt))
    }

    /// The manager is only started when Onecast's AI is on and Codex is a chosen route.
    private static func isCodexEnabled(_ core: AppCore) -> Bool {
        (core.settings.aiEnabled || core.settings.quickActionsEnabled)
            && core.aiSettings.enabledInstalledProviders.contains(.codex)
    }

    private static func settings(from preferences: DockWidgetPreferences) -> PersonalAIUsageSettings {
        PersonalAIUsageSettings(
            content: preferences.string(PersonalAIUsageSettings.Name.content),
            range: preferences.string(PersonalAIUsageSettings.Name.range),
            display: preferences.string(PersonalAIUsageSettings.Name.display),
            measure: preferences.string(PersonalAIUsageSettings.Name.measure))
    }
}

/// What a finished scan hands back to the main actor: plain values only.
private struct ScanOutcome: Sendable {
    let cache: PersonalAIUsageFileCache
    let isComplete: Bool
    let summaries: [PersonalAIUsageSummary]
    let foundFolders: Set<PersonalAIUsageProvider>
}
