import CoreGraphics
import Foundation

/// What custom docks take from a display, so window commands never tile under one.
enum DockInsets {
    /// The edge a dock hugs; `.bottom` is the low-Y side, since this works in Cocoa space.
    enum Edge: Sendable, Equatable {
        case bottom, left, right
    }

    struct Reservation: Sendable, Equatable {
        var edge: Edge
        var frame: CGRect
    }

    /// Each dock's strip comes off the side it hugs; one that would leave no frame is ignored.
    static func usableFrame(visible: CGRect, reserved: [Reservation]) -> CGRect {
        var minX = visible.minX
        var maxX = visible.maxX
        var minY = visible.minY
        // A dock that misses `visible` is on another display or inside what the system excludes.
        for reservation in reserved where reservation.frame.intersects(visible) {
            switch reservation.edge {
            case .bottom: minY = max(minY, reservation.frame.maxY)
            case .left: minX = max(minX, reservation.frame.maxX)
            case .right: maxX = min(maxX, reservation.frame.minX)
            }
        }
        // `CGRect.width` is absolute, so an inverted frame is caught on its edges instead.
        guard maxX > minX, visible.maxY > minY else { return visible }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: visible.maxY - minY)
    }
}
