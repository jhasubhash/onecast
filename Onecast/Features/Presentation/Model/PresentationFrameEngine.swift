import CoreGraphics
import Foundation

/// A presented window's frame in its display's usable area; symmetric, so in any coordinate space.
enum PresentationFrameEngine {
    /// Nil when the size is not a frame at all: full screen, or leaving the window be.
    static func frame(
        for size: PresentationWindowSize, marginPercent: Int, in usable: CGRect
    ) -> CGRect? {
        switch size {
        case .fill:
            return usable
        case .margin:
            let fraction = CGFloat(PresentationMargin.clamped(marginPercent)) / 100
            let dx = (usable.width * fraction).rounded()
            let dy = (usable.height * fraction).rounded()
            return usable.insetBy(dx: dx, dy: dy)
        case .fullScreen, .unchanged:
            return nil
        }
    }
}
