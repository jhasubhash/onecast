import Foundation

/// Which way a price moved, judged on the percent as displayed so "0.00%" never wears an arrow.
enum StockDirection: Sendable, Equatable {
    case up, down, flat

    init(percent: Double?) {
        guard let percent, percent.isFinite else {
            self = .flat
            return
        }
        let shown = StockFormat.roundedPercent(percent)
        self = shown > 0 ? .up : shown < 0 ? .down : .flat
    }

    /// For VoiceOver, where a colour and a glyph carry nothing.
    var spoken: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .flat: "unchanged"
        }
    }
}
