import Foundation

/// Numbers as the System widgets print them: decimal units, as Finder and Activity Monitor do.
enum SystemFormat {
    struct Quantity: Sendable, Equatable {
        let value: String
        let unit: String
    }

    private static let byteUnits = ["B", "KB", "MB", "GB", "TB", "PB"]

    static func bytes(_ count: UInt64) -> String {
        let quantity = byteQuantity(Double(count))
        return "\(quantity.value) \(quantity.unit)"
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let quantity = byteQuantity(bytesPerSecond)
        return "\(quantity.value) \(quantity.unit)/s"
    }

    /// A value and its unit apart, so a tile can set the figure large and the unit small.
    static func byteQuantity(_ amount: Double) -> Quantity {
        var scaled = amount.isFinite ? max(amount, 0) : 0
        var index = 0
        while scaled >= 1000, index < byteUnits.count - 1 {
            scaled /= 1000
            index += 1
        }
        if index > 0, (scaled * 10).rounded() / 10 >= 1000, index < byteUnits.count - 1 {
            scaled /= 1000
            index += 1
        }
        let wholeNumber = index == 0 || scaled >= 100
        let text = String(format: wholeNumber ? "%.0f" : "%.1f", scaled)
        return Quantity(value: text, unit: byteUnits[index])
    }

    /// A fraction as a whole percent, held to 0...100.
    static func percent(_ fraction: Double) -> String {
        "\(percentValue(fraction))%"
    }

    static func percentValue(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    /// The two largest units that apply: "3d 4h", "5h 12m", "12m".
    static func uptime(seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let days = total / 86_400
        let hours = total % 86_400 / 3_600
        let minutes = total % 3_600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Minutes as the menu bar prints a battery estimate: "2:15".
    static func hoursAndMinutes(minutes: Int) -> String {
        let total = max(minutes, 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A playback position: "1:05", or "1:02:03" past an hour.
    static func clock(seconds: Double) -> String {
        let total = seconds.isFinite ? Int(max(seconds, 0)) : 0
        let hours = total / 3_600
        let minutes = total % 3_600 / 60
        let remainder = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
