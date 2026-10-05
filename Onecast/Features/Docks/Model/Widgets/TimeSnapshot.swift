import Foundation

/// A widget's saved state, kept as one JSON string in its instance preferences.
enum TimeSnapshot {
    static func encode(_ value: some Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Nil for a missing or unreadable string, so a bad save reads as a fresh start.
    static func decode<Value: Decodable>(_ text: String?, as type: Value.Type) -> Value? {
        guard let data = text?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
