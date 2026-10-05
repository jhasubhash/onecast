import AppKit
import Foundation
import Observation

/// A cover as the tile draws it, kept with the track it belongs to.
struct SystemNowPlayingArtwork {
    let key: String
    let image: NSImage
}

/// Hears a player app's distributed "something changed" notification even while Onecast is inactive.
@MainActor
private final class PlayerNotificationRelay: NSObject {
    private let onChange: @MainActor () -> Void

    init(names: [String], onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()
        for name in names {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(changed), name: Notification.Name(name), object: nil,
                suspensionBehavior: .deliverImmediately)
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func changed() {
        onChange()
    }
}

/// Spotify and Music playback shared by every Now Playing tile; polls only while one is leased.
@MainActor
@Observable
final class SystemNowPlayingMonitor {
    static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")

    private(set) var statuses: [SystemNowPlaying.Source: SystemNowPlaying.Status] = [:]
    private(set) var artwork: [SystemNowPlaying.Source: SystemNowPlayingArtwork] = [:]

    @ObservationIgnored private var demands: [UUID: Set<SystemNowPlaying.Source>] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let pacer = SystemPacer()
    @ObservationIgnored private var readDates: [SystemNowPlaying.Source: Date] = [:]
    @ObservationIgnored private var artworkRequests: [SystemNowPlaying.Source: String] = [:]
    /// Breaks a tie between two paused players in favour of the one that played last.
    @ObservationIgnored private(set) var lastPlaying: SystemNowPlaying.Source?
    @ObservationIgnored private var artworkTasks: [SystemNowPlaying.Source: Task<Void, Never>] = [:]
    @ObservationIgnored private var relay: PlayerNotificationRelay?
    @ObservationIgnored private var launchObservers: [NotificationToken] = []

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// The sources any live instance wants; nothing else is ever addressed.
    private var wanted: Set<SystemNowPlaying.Source> {
        demands.values.reduce(into: []) { $0.formUnion($1) }
    }

    /// Declares which sources `owner` shows; the returned lease withdraws the claim.
    func demand(_ sources: Set<SystemNowPlaying.Source>, owner: UUID) -> SystemSamplerLease {
        setDemand(sources, owner: owner)
        return SystemSamplerLease { [self] in setDemand(nil, owner: owner) }
    }

    /// Re-declares an owner's sources after its preferences change.
    func setDemand(_ sources: Set<SystemNowPlaying.Source>?, owner: UUID) {
        let before = wanted
        demands[owner] = sources
        let after = wanted
        if before.isEmpty, !after.isEmpty { start() }
        if !before.isEmpty, after.isEmpty { stop() }
        guard !after.isEmpty, before != after else { return }
        for source in before.subtracting(after) { forget(source) }
        pacer.wake()
    }

    func perform(_ control: SystemNowPlaying.Control, source: SystemNowPlaying.Source, skipSeconds: Int) {
        guard let command = command(for: control, source: source, skipSeconds: skipSeconds) else {
            return
        }
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                SystemNowPlayingProbe.send(command, to: source)
            }.value
            if result == .denied { self?.statuses[source] = .denied }
            self?.pacer.wake()
        }
    }

    private func command(
        for control: SystemNowPlaying.Control, source: SystemNowPlaying.Source, skipSeconds: Int
    ) -> SystemNowPlayingProbe.Command? {
        switch control {
        case .playPause: return .playPause
        case .previous: return .previous
        case .next: return .next
        case .skipBack, .skipForward:
            guard let track = statuses[source]?.track else { return nil }
            let elapsed = track.isPlaying ? Date().timeIntervalSince(readDates[source] ?? .now) : 0
            let delta = Double(control == .skipBack ? -skipSeconds : skipSeconds)
            let target = SystemNowPlaying.skipTarget(
                position: track.position + elapsed, by: delta, duration: track.duration)
            return .seek(Int(target.rounded()))
        }
    }

    private func start() {
        relay = PlayerNotificationRelay(
            names: SystemNowPlaying.Source.allCases.map(\.notificationName)
        ) { [weak self] in
            self?.pacer.wake()
        }
        let center = NSWorkspace.shared.notificationCenter
        launchObservers = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
        ].map { name in
            NotificationToken(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let application = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    let bundleID = (application as? NSRunningApplication)?.bundleIdentifier
                    guard SystemNowPlaying.Source.allCases.contains(where: { $0.bundleID == bundleID })
                    else { return }
                    Task { @MainActor in self?.pacer.wake() }
                }, center: center)
        }
        task = Task { await run() }
    }

    private func stop() {
        task?.cancel()
        task = nil
        relay = nil
        launchObservers = []
        for source in SystemNowPlaying.Source.allCases { forget(source) }
    }

    private func forget(_ source: SystemNowPlaying.Source) {
        statuses[source] = nil
        artwork[source] = nil
        readDates[source] = nil
        artworkRequests[source] = nil
        artworkTasks[source]?.cancel()
        artworkTasks[source] = nil
    }

    private func run() async {
        while !Task.isCancelled {
            await refresh()
            if Task.isCancelled { return }
            let interval = wanted.compactMap { statuses[$0].flatMap(SystemNowPlaying.pollInterval) }.min()
            await pacer.wait(interval.map { .seconds($0) } ?? .seconds(3600))
        }
    }

    private func refresh() async {
        for source in SystemNowPlaying.Source.allCases where wanted.contains(source) {
            guard isRunning(source) else {
                publish(.closed, for: source)
                continue
            }
            let status = await Task.detached(priority: .utility) {
                SystemNowPlayingProbe.status(of: source)
            }.value
            if Task.isCancelled { return }
            guard wanted.contains(source) else { continue }
            publish(status, for: source)
        }
    }

    private func isRunning(_ source: SystemNowPlaying.Source) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID)
            .contains { !$0.isTerminated }
    }

    private func publish(_ status: SystemNowPlaying.Status, for source: SystemNowPlaying.Source) {
        readDates[source] = .now
        if status.track?.isPlaying == true { lastPlaying = source }
        if statuses[source] != status { statuses[source] = status }
        guard let track = status.track else {
            artworkRequests[source] = nil
            artworkTasks[source]?.cancel()
            artworkTasks[source] = nil
            if artwork[source] != nil { artwork[source] = nil }
            return
        }
        loadArtwork(for: track)
    }

    private func loadArtwork(for track: SystemNowPlaying.Track) {
        let source = track.source
        let key = track.artworkKey
        guard artworkRequests[source] != key else { return }
        artworkRequests[source] = key
        artworkTasks[source]?.cancel()
        if artwork[source]?.key != key { artwork[source] = nil }
        artworkTasks[source] = Task { [weak self] in
            let image = await Self.fetchArtwork(for: track)
            guard !Task.isCancelled, let self, self.artworkRequests[source] == key else { return }
            self.artwork[source] = image.map {
                SystemNowPlayingArtwork(key: key, image: NSImage(cgImage: $0, size: .zero))
            }
        }
    }

    private nonisolated static func fetchArtwork(for track: SystemNowPlaying.Track) async -> CGImage? {
        let data: Data?
        switch track.source {
        case .spotify:
            guard let url = track.artworkURL,
                let (body, response) = try? await session.data(from: url),
                (response as? HTTPURLResponse)?.statusCode == 200
            else { return nil }
            data = body
        case .music:
            data = SystemNowPlayingProbe.musicArtwork()
        }
        return data.flatMap(SystemNowPlayingProbe.decodeArtwork)
    }
}
