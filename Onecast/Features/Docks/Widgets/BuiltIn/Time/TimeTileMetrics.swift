import OnecastPluginKit
import SwiftUI

/// Type and spacing for a time tile, derived from the dock's tile length so it scales with it.
struct TimeTileMetrics {
    enum Role {
        /// A clock's digits, which have the whole tile to themselves.
        case hero
        /// The one figure a compact tile exists to show.
        case display
        case value
        case label
        case caption

        fileprivate var scale: CGFloat {
            switch self {
            case .hero: 0.38
            case .display: 0.30
            case .value: 0.22
            case .label: 0.17
            case .caption: 0.14
            }
        }
    }

    let tileLength: CGFloat
    let size: DockWidgetSize
    let isVertical: Bool

    init(_ context: DockWidgetContext) {
        tileLength = context.tileLength
        size = context.size
        isVertical = context.edge.isVertical
    }

    var padding: CGFloat { tileLength * 0.12 }
    var spacing: CGFloat { tileLength * 0.06 }
    var dot: CGFloat { tileLength * 0.07 }
    var barHeight: CGFloat { tileLength * 0.05 }
    var isCompact: Bool { size == .compact }

    /// A side dock gives a wide tile two tiles of height, room for more rows than a square has.
    var isTall: Bool { isVertical && size != .compact }

    /// How many tile-sized cells the widget spans along the dock.
    var cells: Int {
        switch size {
        case .compact: 1
        case .wide: 2
        case .expanded: 4
        }
    }

    func font(_ role: Role, weight: Font.Weight = .semibold) -> Font {
        .system(size: tileLength * role.scale, weight: weight, design: .rounded)
    }

    /// A glyph's point size, as a fraction of the tile.
    func symbolSize(_ fraction: CGFloat) -> CGFloat { tileLength * fraction }

    /// Where every time popover agrees: one width and one inset, so the seven read as a family.
    enum Popover {
        static let width: CGFloat = 260
        static let padding: CGFloat = Theme.Spacing.xl
        /// A laps list scrolls past this height instead of growing the popover.
        static let listMaxHeight: CGFloat = 200
        static let clockFace: CGFloat = 150
        /// The bell above an alarm's popover.
        static let glyph: CGFloat = 28
    }
}
