import SwiftUI

/// The colour each System reading wears, by how much attention it deserves.
enum SystemTint {
    static func load(_ fraction: Double) -> Color {
        switch SystemLoadLevel(fraction: fraction) {
        case .calm: Theme.Colors.success
        case .busy: Theme.Colors.warning
        case .saturated: Theme.Colors.destructive
        }
    }

    static func pressure(_ pressure: SystemMemoryUsage.Pressure) -> Color {
        switch pressure {
        case .normal: Theme.Colors.success
        case .warning: Theme.Colors.warning
        case .critical: Theme.Colors.destructive
        }
    }

    static let download = Theme.Colors.progress
    static let upload = Theme.Colors.success
}
