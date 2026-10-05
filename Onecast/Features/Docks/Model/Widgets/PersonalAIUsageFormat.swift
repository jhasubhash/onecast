import Foundation

enum PersonalAIUsageFormat {
    private static let units: [(suffix: String, size: Int)] = [
        ("K", 1_000), ("M", 1_000_000), ("B", 1_000_000_000), ("T", 1_000_000_000_000),
    ]
    /// Far past any real count, and low enough that scaling a count by ten cannot overflow.
    private static let maxCount = 100_000_000_000_000_000

    /// A token count in its shortest honest form: 842, 1.2K, 12K, 1.2M, 3B. Never "1000K".
    static func tokens(_ requested: Int) -> String {
        let count = min(requested, maxCount)
        guard count >= 1_000 else { return String(max(count, 0)) }
        var index = 0
        while index < units.count - 1, scaledWhole(count, units[index].size) >= 1_000 {
            index += 1
        }
        let size = units[index].size
        let tenths = (count * 10 + size / 2) / size
        if tenths < 100 {
            let text = tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
            return text + units[index].suffix
        }
        return "\(scaledWhole(count, size))\(units[index].suffix)"
    }

    /// A count with grouping separators, for a value read aloud or hovered.
    static func exact(_ count: Int, locale: Locale) -> String {
        count.formatted(.number.locale(locale))
    }

    private static func scaledWhole(_ count: Int, _ size: Int) -> Int {
        (count + size / 2) / size
    }
}
