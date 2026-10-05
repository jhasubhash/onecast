import Foundation

/// Spotify and Apple Music playback as the Now Playing widget models it; no Apple Events here.
enum SystemNowPlaying {
    enum Source: String, Sendable, CaseIterable, Identifiable {
        case spotify, music

        var id: String { rawValue }

        var bundleID: String {
            switch self {
            case .spotify: "com.spotify.client"
            case .music: "com.apple.Music"
            }
        }

        var title: String {
            switch self {
            case .spotify: "Spotify"
            case .music: "Music"
            }
        }

        /// The distributed notification the app posts when its player changes state or track.
        var notificationName: String {
            switch self {
            case .spotify: "com.spotify.client.PlaybackStateChanged"
            case .music: "com.apple.Music.playerInfo"
            }
        }
    }

    enum PlayerState: String, Sendable, Equatable {
        case playing, paused
    }

    struct Track: Sendable, Equatable {
        let source: Source
        let state: PlayerState
        let title: String
        let artist: String
        let album: String
        /// Seconds into the track when it was read.
        let position: Double
        let duration: Double
        let artworkURL: URL?
        /// The player's own track id, so artwork is fetched once per track, not once per tick.
        let identity: String

        var isPlaying: Bool { state == .playing }

        /// 0...1; zero for a stream that reports no length.
        var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(position / duration, 0), 1)
        }

        var artworkKey: String { "\(source.rawValue):\(identity)" }
    }

    /// What one source reported on its last read.
    enum Status: Sendable, Equatable {
        /// Not running, so it was never asked: asking would launch it.
        case closed
        /// The user has not allowed Onecast to control it, or turned that off.
        case denied
        case stopped
        case track(Track)
        /// Running but its answer could not be read.
        case failed

        var track: Track? {
            if case .track(let track) = self { return track }
            return nil
        }
    }

    /// The scripts answer `{state, title, artist, album, positionMS, durationMS, id, artworkURL}`.
    static func parse(source: Source, fields: [String]) -> Status {
        guard let state = fields.first else { return .failed }
        switch state {
        case "closed": return .closed
        case "stopped": return .stopped
        case "playing", "paused": break
        default: return .stopped
        }
        guard fields.count >= 7, let playerState = PlayerState(rawValue: state),
            let positionMS = Int(fields[4]), let durationMS = Int(fields[5])
        else { return .failed }
        let duration = Double(max(durationMS, 0)) / 1000
        var position = Double(max(positionMS, 0)) / 1000
        if duration > 0 { position = min(position, duration) }
        let artwork = fields.count > 7 ? URL(string: fields[7]) : nil
        return .track(
            Track(
                source: source, state: playerState, title: fields[1], artist: fields[2],
                album: fields[3], position: position, duration: duration,
                artworkURL: artwork?.scheme == "https" ? artwork : nil,
                identity: fields[6].isEmpty ? "\(fields[1])|\(fields[2])|\(fields[3])" : fields[6]))
    }

    /// Where a seek lands: held inside the track, and short of the end so it never skips one.
    static func skipTarget(position: Double, by delta: Double, duration: Double) -> Double {
        let target = position + delta
        guard duration > 0 else { return max(target, 0) }
        return min(max(target, 0), max(duration - 1, 0))
    }

    /// Playing beats paused beats a permission problem beats idle; a tie keeps the shown source.
    static func active(
        _ statuses: [Source: Status], previous: Source?
    ) -> (source: Source, status: Status)? {
        let ranked = Source.allCases.compactMap { source in
            statuses[source].map { (source: source, status: $0) }
        }
        .filter { $0.status != .closed }
        let best = ranked.map { rank($0.status) }.max()
        let top = ranked.filter { rank($0.status) == best }
        return top.first { $0.source == previous } ?? top.first
    }

    /// Seconds until a source should be read again; nil for one that is closed.
    static func pollInterval(for status: Status) -> TimeInterval? {
        switch status {
        case .closed: nil
        case .track(let track): track.isPlaying ? 1 : 5
        case .denied, .stopped, .failed: 5
        }
    }

    private static func rank(_ status: Status) -> Int {
        switch status {
        case .track(let track): track.isPlaying ? 6 : 5
        case .denied: 4
        case .stopped: 3
        case .failed: 2
        case .closed: 1
        }
    }
}
