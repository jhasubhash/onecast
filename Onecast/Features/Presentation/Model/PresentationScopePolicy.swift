import CoreGraphics
import Foundation

/// Which of the windows on screen a scope puts away, and whether an AX window is one of them.
enum PresentationScopePolicy {
    /// Window frames per app the scope reaches; nil when it reaches every window of every app.
    static func reach(
        _ scope: PresentationScope, onScreen: [PresentationWindow], display: CGRect
    ) -> [Int32: [CGRect]]? {
        let windows: [PresentationWindow]
        switch scope {
        case .everywhere:
            return nil
        case .currentSpace:
            windows = onScreen
        case .presentationDisplay:
            windows = onScreen.filter { display.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        }
        return Dictionary(grouping: windows, by: \.pid).mapValues { $0.map(\.frame) }
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
