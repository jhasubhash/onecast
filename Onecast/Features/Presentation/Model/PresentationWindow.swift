import CoreGraphics
import Foundation

/// One ordinary window of another app, in the top-left global space AX and Quartz share.
struct PresentationWindow: Equatable, Sendable {
    let pid: Int32
    let frame: CGRect
    /// On the Space a display shows now; false for one on another Space, or minimized.
    let isOnScreen: Bool
}
