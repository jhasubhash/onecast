import Foundation
import Observation
import OnecastPluginKit

/// One AI Usage widget's live state: Codex's or Copilot's limits, and token activity from logs.
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
        let source: PersonalAIUsageLimitsSource
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

    /// Where a remote source's limits stand (Claude, Copilot), for the tile and popover to explain.
    enum RemoteStatus: Equatable {
        case checking
        case ready(PersonalAIUsageLimitsReport)
        case failed(PersonalAIUsageLimitsProblem)
    }

    private(set) var settings = PersonalAIUsageSettings()
    private(set) var activity: Activity?
    private(set) var isScanning = false
    /// When this widget last asked its limits source to check, which is when limits were fetched.
    private(set) var limitsRequestedAt: Date?
    private(set) var remoteStatus: [PersonalAIUsageLimitsSource: RemoteStatus] = [:]
    private var checkingSources: Set<PersonalAIUsageLimitsSource> = []

    @ObservationIgnored private var fileCache = PersonalAIUsageFileCache()
    @ObservationIgnored private var wake: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var runGeneration = 0
    @ObservationIgnored private var isForcingLimits = false

    /// The chosen source's limit windows, the tightest first; nil when there are none to show.
    var limits: [LimitRow]? {
        guard settings.limitsSource != .codex else { return codexLimits }
        guard case .ready(let report) = currentRemoteStatus, !report.windows.isEmpty else {
            return nil
        }
        return report.windows.map {
            LimitRow(
                id: $0.id, source: settings.limitsSource, fallbackTitle: $0.fallbackTitle,
                window: PersonalAIUsageLimitWindow(
                    usedPercent: $0.usedPercent, durationMinutes: $0.durationMinutes,
                    resetsAt: $0.resetsAt))
        }
    }

    /// The chosen remote source's state; Codex reports through `codexStatus` instead.
    var currentRemoteStatus: RemoteStatus {
        remoteStatus[settings.limitsSource] ?? .checking
    }

    private var codexLimits: [LimitRow]? {
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

    /// The plan of whichever account the limits come from: "Plus", "Business".
    var limitsPlan: String? {
        guard settings.limitsSource != .codex else {
            return AppCore.shared.chatGPTSubscription.account?.planTitle
        }
        if case .ready(let report) = currentRemoteStatus { return report.plan }
        return nil
    }

    /// The newest of the last scan and the last limits check.
    var updatedAt: Date? { [activity?.updatedAt, limitsRequestedAt].compactMap { $0 }.max() }

    var isRefreshing: Bool {
        isScanning || checkingSources.contains(settings.limitsSource)
            || (settings.limitsSource == .codex
                && AppCore.shared.chatGPTSubscription.phase == .starting)
    }

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
        let rescans =
            next.range != settings.range || next.content != settings.content
            || next.limitsSource != settings.limitsSource
        if next.limitsSource != settings.limitsSource { isForcingLimits = true }
        if next != settings { settings = next }
        return rescans
    }

    /// Never asks while a check is under way, and never touches a source the widget is not showing.
    private func refreshLimits() {
        let force = isForcingLimits
        isForcingLimits = false
        guard settings.limitsSource == .codex else {
            return refreshRemote(settings.limitsSource, force: force)
        }
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

    private func refreshRemote(_ source: PersonalAIUsageLimitsSource, force: Bool) {
        guard !checkingSources.contains(source) else { return }
        let now = Date()
        guard force || PersonalAIUsageSchedule.isStale(since: limitsRequestedAt, now: now) else {
            return
        }
        limitsRequestedAt = now
        checkingSources.insert(source)
        Task { [weak self] in
            let result =
                source == .claude
                ? await PersonalClaudeUsageClient.fetch() : await PersonalCopilotUsageClient.fetch()
            guard let self else { return }
            checkingSources.remove(source)
            switch result {
            case .success(let report): remoteStatus[source] = .ready(report)
            case .failure(let problem): remoteStatus[source] = .failed(problem)
            }
        }
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
            id: id, source: .codex, fallbackTitle: fallback,
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
            measure: preferences.string(PersonalAIUsageSettings.Name.measure),
            limitsSource: preferences.string(PersonalAIUsageSettings.Name.limitsSource))
    }
}

/// What a finished scan hands back to the main actor: plain values only.
private struct ScanOutcome: Sendable {
    let cache: PersonalAIUsageFileCache
    let isComplete: Bool
    let summaries: [PersonalAIUsageSummary]
    let foundFolders: Set<PersonalAIUsageProvider>
}
