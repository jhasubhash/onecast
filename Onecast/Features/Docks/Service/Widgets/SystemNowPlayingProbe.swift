import CoreGraphics
import Foundation
import ImageIO

/// The Apple Events behind Now Playing. Only Spotify and Music are ever addressed, by bundle id.
enum SystemNowPlayingProbe {
    enum Command: Sendable, Equatable {
        case playPause, previous, next
        /// Jump to this many whole seconds into the current track.
        case seek(Int)
    }

    enum CommandResult: Sendable, Equatable {
        case done, denied, failed
    }

    /// `errAEEventNotPermitted`: the user declined, or later revoked, Automation access.
    private static let notPermitted = -1743
    /// `procNotFound`: the app quit between the running check and the event.
    private static let notRunning = -600
    private static let artworkLongestSide = 512

    /// Reads one source; a closed one is never addressed, since an Apple event would launch it.
    static func status(of source: SystemNowPlaying.Source) -> SystemNowPlaying.Status {
        var failure: NSDictionary?
        guard let script = NSAppleScript(source: statusScript(source)) else { return .failed }
        let result = script.executeAndReturnError(&failure)
        if let failure { return status(for: failure) }
        guard result.numberOfItems > 0 else { return .failed }
        let fields = (1...result.numberOfItems).map { result.atIndex($0)?.stringValue ?? "" }
        return SystemNowPlaying.parse(source: source, fields: fields)
    }

    static func send(_ command: Command, to source: SystemNowPlaying.Source) -> CommandResult {
        var failure: NSDictionary?
        guard let script = NSAppleScript(source: commandScript(command, source: source)) else {
            return .failed
        }
        script.executeAndReturnError(&failure)
        guard let failure else { return .done }
        return status(for: failure) == .denied ? .denied : .failed
    }

    /// The current Music track's cover as encoded image bytes; nil when it has none.
    static func musicArtwork() -> Data? {
        var failure: NSDictionary?
        let id = SystemNowPlaying.Source.music.bundleID
        let source = """
            if application id "\(id)" is not running then return missing value
            with timeout of 10 seconds
                tell application id "\(id)"
                    if (count of artworks of current track) is 0 then return missing value
                    return raw data of artwork 1 of current track
                end tell
            end timeout
            """
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&failure)
        guard failure == nil, result.descriptorType != typeNull else { return nil }
        let data = result.data
        return data.isEmpty ? nil : data
    }

    /// Decodes a cover no larger than the tile ever needs, so a 3000px scan is never resident.
    static func decodeArtwork(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: artworkLongestSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func status(for failure: NSDictionary) -> SystemNowPlaying.Status {
        switch failure[NSAppleScript.errorNumber] as? Int {
        case notPermitted: .denied
        case notRunning: .closed
        default: .failed
        }
    }

    private static func statusScript(_ source: SystemNowPlaying.Source) -> String {
        let id = source.bundleID
        let tail: String
        switch source {
        case .spotify:
            tail = """
                set artworkURL to ""
                try
                    set artworkURL to artwork url of t
                end try
                return {stateName, name of t, artist of t, album of t, positionMS, \
                duration of t, id of t, artworkURL}
                """
        case .music:
            tail = """
                set durationMS to 0
                try
                    set durationMS to (round ((duration of t) * 1000)) as integer
                end try
                set trackID to ""
                try
                    set trackID to persistent ID of t
                end try
                return {stateName, name of t, artist of t, album of t, positionMS, durationMS, trackID}
                """
        }
        return """
            if application id "\(id)" is not running then return {"closed"}
            with timeout of 10 seconds
                tell application id "\(id)"
                    set stateName to "playing"
                    if player state is stopped then
                        set stateName to "stopped"
                    else if player state is paused then
                        set stateName to "paused"
                    end if
                    if stateName is "stopped" then return {stateName}
                    set t to current track
                    set positionMS to 0
                    try
                        set positionMS to (round ((player position) * 1000)) as integer
                    end try
                    \(tail)
                end tell
            end timeout
            """
    }

    private static func commandScript(_ command: Command, source: SystemNowPlaying.Source) -> String {
        let verb =
            switch command {
            case .playPause: "playpause"
            case .previous: "previous track"
            case .next: "next track"
            case .seek(let seconds): "set player position to \(max(seconds, 0))"
            }
        let id = source.bundleID
        return """
            if application id "\(id)" is not running then return
            with timeout of 10 seconds
                tell application id "\(id)" to \(verb)
            end timeout
            """
    }
}
