import CoreGraphics
import Foundation

/// Which windows the display and Space choices reach, and whether an AX window is one of them.
enum PresentationScopePolicy {
    /// Window frames per app the choices reach; nil when they reach every window of every app.
    static func reach(
        displays: PresentationReach, spaces: PresentationReach, windows: [PresentationWindow],
        display: CGRect
    ) -> [Int32: [CGRect]]? {
        if displays == .all, spaces == .all { return nil }
        let reached = windows.filter { window in
            (spaces == .all || window.isOnScreen)
                && (displays == .all
                    || display.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)))
        }
        return Dictionary(grouping: reached, by: \.pid).mapValues { $0.map(\.frame) }
    }

    /// AX gives an app only the windows of the Spaces on screen; hiding is the reach into the rest.
    static func hidesWholeApp(spaces: PresentationReach) -> Bool {
        spaces == .all
    }

    /// Two readings of one window can differ by a point of rounding between AX and Quartz.
    static func matches(_ frame: CGRect, anyOf frames: [CGRect], tolerance: CGFloat = 2) -> Bool {
        frames.contains {
            abs($0.minX - frame.minX) <= tolerance && abs($0.minY - frame.minY) <= tolerance
                && abs($0.width - frame.width) <= tolerance
                && abs($0.height - frame.height) <= tolerance
        }
    }
}
