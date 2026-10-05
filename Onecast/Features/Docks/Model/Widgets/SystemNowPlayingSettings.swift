import Foundation

extension SystemNowPlaying {
    /// One Now Playing instance's preferences, read through a lookup so this needs no defaults.
    struct Settings: Sendable, Equatable {
        enum Layout: String, Sendable, CaseIterable {
            case mini, full
        }

        enum Name {
            static let spotify = "spotify"
            static let music = "music"
            static let layout = "layout"
            static let showsPreviousNext = "showsPreviousNext"
            static let skipSeconds = "skipSeconds"
            static let hidesWhenClosed = "hidesWhenClosed"
        }

        /// The dropdown's choices, in seconds; zero turns the skip buttons off.
        static let skipOptions = [0, 5, 10, 15, 30, 60]

        var sources: [Source]
        var layout: Layout
        var showsPreviousNext: Bool
        var skipSeconds: Int
        var hidesWhenClosed: Bool

        /// An unset or malformed value reads as its default, so a fresh instance still works.
        init(value: (String) -> Any?) {
            let wantsSpotify = value(Name.spotify) as? Bool ?? true
            let wantsMusic = value(Name.music) as? Bool ?? true
            sources = Source.allCases.filter { $0 == .spotify ? wantsSpotify : wantsMusic }
            layout = (value(Name.layout) as? String).flatMap(Layout.init) ?? .mini
            showsPreviousNext = value(Name.showsPreviousNext) as? Bool ?? true
            let skip = (value(Name.skipSeconds) as? String).flatMap { Int($0) } ?? 0
            skipSeconds = Self.skipOptions.contains(skip) ? skip : 0
            hidesWhenClosed = value(Name.hidesWhenClosed) as? Bool ?? false
        }

        var skipsEnabled: Bool { skipSeconds > 0 }
    }
}
