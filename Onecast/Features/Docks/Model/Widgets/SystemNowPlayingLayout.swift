import Foundation

extension SystemNowPlaying {
    enum Control: Sendable, Equatable, CaseIterable {
        case skipBack, previous, playPause, next, skipForward
    }

    /// What a tile draws at a given size: which of artwork, text, progress and controls fit.
    struct TileLayout: Sendable, Equatable {
        let artworkSide: Double
        let showsText: Bool
        let showsProgress: Bool
        /// In drawing order, left to right or, down a side dock, along the foot row.
        let controls: [Control]
        /// With text shown but no room for a play button, the artwork itself plays and pauses.
        let artworkTogglesPlayback: Bool

        /// A tile this much longer than thick has room for more than its artwork.
        private static let wideRatio = 1.5
        /// The text block's shortest span, in control sizes, before controls take its place.
        private static let minimumTextControls = 1.6
        /// A tile this many control sizes thick has room for a progress bar under its text.
        private static let progressThicknessControls = 2.5
        /// The height a progress bar and its times take, in control sizes.
        private static let progressControls = 0.75

        /// `length` runs along the dock, `thickness` across it; `inset`, `control` are view sizes.
        static func resolve(
            length: Double, thickness: Double, isVertical: Bool, settings: Settings,
            inset: Double, control: Double
        ) -> TileLayout {
            let artworkSide = max(thickness - 2 * inset, 0)
            guard length >= thickness * wideRatio else {
                return TileLayout(
                    artworkSide: artworkSide, showsText: false,
                    showsProgress: settings.layout == .full, controls: [],
                    artworkTogglesPlayback: false)
            }
            let room = max(length - artworkSide - 3 * inset, 0)
            let minimumText = control * minimumTextControls
            let showsText = room >= minimumText
            let leftover = showsText ? room - minimumText - inset : room
            // A side dock stacks the row under the text, so it spends height and has thickness to fill.
            let budget = isVertical ? (leftover >= control ? thickness - 2 * inset : 0) : leftover
            let controls = fitting(settings: settings, budget: budget, inset: inset, control: control)
            let showsProgress =
                settings.layout == .full && showsText
                && (isVertical
                    ? leftover - (controls.isEmpty ? 0 : control + inset) >= control * progressControls
                    : thickness >= control * progressThicknessControls)
            return TileLayout(
                artworkSide: artworkSide, showsText: showsText, showsProgress: showsProgress,
                controls: controls, artworkTogglesPlayback: showsText && !controls.contains(.playPause))
        }

        /// Play/pause first, then previous/next, then skips, each only if the whole group fits.
        private static func fitting(
            settings: Settings, budget: Double, inset: Double, control: Double
        ) -> [Control] {
            func occupied(_ count: Int) -> Double {
                Double(count) * control + Double(max(count - 1, 0)) * inset
            }
            guard budget >= occupied(1) else { return [] }
            var chosen: [Control] = [.playPause]
            var groups: [[Control]] = []
            if settings.showsPreviousNext { groups.append([.previous, .next]) }
            if settings.skipsEnabled { groups.append([.skipBack, .skipForward]) }
            for group in groups where budget >= occupied(chosen.count + group.count) {
                chosen += group
            }
            return Control.allCases.filter(chosen.contains)
        }
    }
}
