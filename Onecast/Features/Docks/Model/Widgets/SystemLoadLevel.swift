import Foundation

/// How worried a load figure should look: calm, busy, or saturated.
enum SystemLoadLevel: Sendable, Equatable {
    case calm, busy, saturated

    static let busyThreshold = 0.6
    static let saturatedThreshold = 0.85

    init(fraction: Double) {
        if fraction >= Self.saturatedThreshold {
            self = .saturated
        } else if fraction >= Self.busyThreshold {
            self = .busy
        } else {
            self = .calm
        }
    }
}
