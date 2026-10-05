import OnecastPluginKit
import SwiftUI

/// Type and spacing for a Personal tile, derived from the dock's tile length so it scales with it.
struct PersonalTileMetrics {
    enum Role {
        /// The one figure a tile exists to show.
        case display
        case value
        case label
        case caption

        fileprivate var scale: CGFloat {
            switch self {
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
    /// A tile header's accent dot.
    var dotSize: CGFloat { tileLength * 0.09 }
    var isCompact: Bool { size == .compact }

    func font(_ role: Role, weight: Font.Weight = .semibold) -> Font {
        .system(size: tileLength * role.scale, weight: weight, design: .rounded)
    }

    /// A glyph's point size, as a fraction of the tile.
    func symbolSize(_ fraction: CGFloat) -> CGFloat { tileLength * fraction }
}
