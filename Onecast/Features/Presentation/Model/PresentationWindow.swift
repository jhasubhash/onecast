import CoreGraphics
import Foundation

/// One on-screen window of another app, in the top-left global space AX and Quartz share.
struct PresentationWindow: Equatable, Sendable {
    let pid: Int32
    let frame: CGRect
}
