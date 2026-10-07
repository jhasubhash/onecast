import Foundation

/// One display mode as the resolution picker lists it: a size in points at a backing scale.
struct PresentationDisplayMode: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double

    var scale: Int {
        guard width > 0 else { return 1 }
        return max(1, Int((Double(pixelWidth) / Double(width)).rounded()))
    }

    var isHiDPI: Bool { scale > 1 }

    /// What a preference stores. Never the refresh rate, which a different cable changes.
    var id: String { "\(width)x\(height)@\(scale)x" }

    var title: String {
        isHiDPI ? "\(width) × \(height)" : "\(width) × \(height) (low resolution)"
    }
}
