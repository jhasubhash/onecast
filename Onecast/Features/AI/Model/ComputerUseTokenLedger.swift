import Foundation

/// The bridge's token gate, extracted so its refusals are testable without a live socket.
@MainActor
struct ComputerUseTokenLedger {
    private struct Entry {
        let armed: @MainActor () -> Bool
        let issuedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let capacity: Int
    private let lifetime: TimeInterval

    init(capacity: Int = 32, lifetime: TimeInterval = 900) {
        self.capacity = capacity
        self.lifetime = lifetime
    }

    mutating func issue(_ token: String, armed: @escaping @MainActor () -> Bool, now: Date) {
        entries[token] = Entry(armed: armed, issuedAt: now)
        order.append(token)
        while order.count > capacity { entries.removeValue(forKey: order.removeFirst()) }
    }

    /// A known token whose route is armed now and was issued within the lifetime; all else refuses.
    func authorizes(_ token: String, now: Date) -> Bool {
        guard let entry = entries[token], now.timeIntervalSince(entry.issuedAt) < lifetime else {
            return false
        }
        return entry.armed()
    }
}
