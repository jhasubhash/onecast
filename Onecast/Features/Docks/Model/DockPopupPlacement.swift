import CoreGraphics
import Foundation

/// Where a popup a dock opens — a menu, a folder, a widget's popover, a tile's label — sits.
enum DockPopupPlacement {
    /// The popup sits on the side of the anchor facing away from the screen edge the dock hugs,
    /// centred on it, then slides along the edge to stay within `visible`.
    static func frame(
        size: CGSize, anchor: CGRect, edge: DockEdge, visible: CGRect, gap: CGFloat,
        margin: CGFloat
    ) -> CGRect {
        var origin: CGPoint
        switch edge {
        case .bottom:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .left:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        }
        let room = visible.insetBy(dx: margin, dy: margin)
        origin.x = clamp(origin.x, room.minX, room.maxX - size.width)
        origin.y = clamp(origin.y, room.minY, room.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    /// A popup taller than the room it has is cut to it, so a long list scrolls instead.
    static func fittedSize(_ size: CGSize, in visible: CGRect, margin: CGFloat) -> CGSize {
        CGSize(
            width: min(size.width, max(visible.width - 2 * margin, 0)),
            height: min(size.height, max(visible.height - 2 * margin, 0)))
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        guard high >= low else { return low }
        return min(max(value, low), high)
    }
}
