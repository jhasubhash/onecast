import AppKit
import Foundation
import Observation
import OnecastPluginKit

/// One Now Playing instance: its preferences, and what it should show from the shared monitor.
@MainActor
@Observable
final class NowPlayingWidgetModel {
    enum Content {
        /// Reading has not finished for every source this instance shows.
        case loading
        case hidden
        case noSources
        case closed(SystemNowPlaying.Source)
        case denied(SystemNowPlaying.Source)
        case stopped(SystemNowPlaying.Source)
        case failed(SystemNowPlaying.Source)
        case track(SystemNowPlaying.Track, artwork: NSImage?)
    }

    @ObservationIgnored private let monitor = DockWidgetServices.current.nowPlaying
    @ObservationIgnored private let owner = UUID()
    @ObservationIgnored private var instanceID = ""
    @ObservationIgnored private var lease: SystemSamplerLease?
    @ObservationIgnored private var defaultsObserver: NotificationToken?
    @ObservationIgnored private var appliedSettings: SystemNowPlaying.Settings?
    /// Bumped when a preference this widget reads changes, so views reading `settings` redraw.
    private var revision = 0
    /// The dock asks for the popover on every click in the tile, a control's included; this lets
    /// the widget decline while the pointer is on one.
    @ObservationIgnored var isPointerOnControl = false

    /// Called as the host asks for the tile; sets nothing a view observes.
    func configure(instanceID: String) {
        self.instanceID = instanceID
    }

    var settings: SystemNowPlaying.Settings {
        _ = revision
        return readSettings()
    }

    var content: Content {
        let settings = settings
        guard let first = settings.sources.first else { return .noSources }
        let wanted = Set(settings.sources)
        let statuses = monitor.statuses.filter { wanted.contains($0.key) }
        guard let active = SystemNowPlaying.active(statuses, previous: monitor.lastPlaying) else {
            if wanted.contains(where: { monitor.statuses[$0] == nil }) { return .loading }
            return settings.hidesWhenClosed ? .hidden : .closed(first)
        }
        switch active.status {
        case .track(let track):
            let artwork = monitor.artwork[active.source]
            return .track(track, artwork: artwork?.key == track.artworkKey ? artwork?.image : nil)
        case .denied: return .denied(active.source)
        case .stopped: return .stopped(active.source)
        case .failed: return .failed(active.source)
        case .closed: return .closed(first)
        }
    }

    /// Starts reading the sources this instance shows; idempotent.
    func start() {
        guard lease == nil else { return }
        let current = readSettings()
        appliedSettings = current
        lease = monitor.demand(Set(current.sources), owner: owner)
        defaultsObserver = NotificationToken(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.defaultsChanged() }
            }, center: .default)
    }

    func stop() {
        isPointerOnControl = false
        lease?.end()
        lease = nil
        defaultsObserver = nil
    }

    func perform(_ control: SystemNowPlaying.Control, on source: SystemNowPlaying.Source) {
        monitor.perform(control, source: source, skipSeconds: settings.skipSeconds)
    }

    private func defaultsChanged() {
        let current = readSettings()
        guard current != appliedSettings else { return }
        appliedSettings = current
        revision += 1
        monitor.setDemand(Set(current.sources), owner: owner)
    }

    private func readSettings() -> SystemNowPlaying.Settings {
        let instanceID = instanceID
        return SystemNowPlaying.Settings { name in
            UserDefaults.standard.object(
                forKey: DockWidgetPreferences.key(instanceID: instanceID, name: name))
        }
    }
}
