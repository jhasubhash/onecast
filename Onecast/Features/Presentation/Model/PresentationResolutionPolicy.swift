import Foundation

/// Which modes the resolution picker offers, and which concrete mode a stored choice resolves to.
enum PresentationResolutionPolicy {
    /// One entry per id, largest first, a HiDPI mode ahead of the same size at 1x.
    static func choices(from modes: [PresentationDisplayMode]) -> [PresentationDisplayMode] {
        var best: [String: PresentationDisplayMode] = [:]
        for mode in modes {
            if let kept = best[mode.id], !isBetter(mode, than: kept) { continue }
            best[mode.id] = mode
        }
        return best.values.sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            return lhs.scale > rhs.scale
        }
    }

    /// The mode to switch to for `id`, or nil when this display cannot show it.
    static func index(of id: String, in modes: [PresentationDisplayMode]) -> Int? {
        modes.indices
            .filter { modes[$0].id == id }
            .max { isBetter(modes[$1], than: modes[$0]) }
    }

    /// The fastest refresh, then the sharpest backing store.
    private static func isBetter(
        _ candidate: PresentationDisplayMode, than other: PresentationDisplayMode
    ) -> Bool {
        if candidate.refreshRate != other.refreshRate {
            return candidate.refreshRate > other.refreshRate
        }
        return candidate.pixelWidth > other.pixelWidth
    }
}
