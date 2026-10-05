import Foundation

/// One logged drink; `milliliters` is nil when the instance counts drinks rather than measuring.
struct HydrationEntry: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let date: Date
    let milliliters: Int?
}

/// The drinks of one calendar day, newest first.
struct HydrationDay: Sendable, Equatable, Identifiable {
    let start: Date
    let entries: [HydrationEntry]

    var id: Date { start }
    var count: Int { entries.count }
    var milliliters: Int { entries.reduce(0) { $0 + ($1.milliliters ?? 0) } }
}

/// What a tap on Undo reverses.
enum HydrationChange: Sendable, Equatable {
    case added(HydrationEntry)
    case removed(HydrationEntry)
}

/// The days a history list shows, and whether older ones are waiting behind "Show older drinks".
struct HydrationHistory: Sendable, Equatable {
    let days: [HydrationDay]
    let hasOlder: Bool
}

/// Every drink an instance has logged.
struct HydrationLog: Sendable, Equatable {
    /// Newest first, so a history list reads straight off it.
    private(set) var entries: [HydrationEntry]

    init(entries: [HydrationEntry] = []) {
        self.entries = entries.sorted { $0.date > $1.date }
    }

    var lastDrink: Date? { entries.first?.date }

    /// A second add of the same entry is ignored, so an Undo can never double a drink.
    mutating func add(_ entry: HydrationEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        let index = entries.firstIndex { $0.date <= entry.date } ?? entries.endIndex
        entries.insert(entry, at: index)
    }

    @discardableResult
    mutating func remove(id: UUID) -> HydrationEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    mutating func revert(_ change: HydrationChange) {
        switch change {
        case .added(let entry): remove(id: entry.id)
        case .removed(let entry): add(entry)
        }
    }

    /// Newest day first; a day without a drink has no row.
    func days(calendar: Calendar) -> [HydrationDay] {
        var days: [HydrationDay] = []
        var start: Date?
        var bucket: [HydrationEntry] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if day != start {
                if let start { days.append(HydrationDay(start: start, entries: bucket)) }
                start = day
                bucket = []
            }
            bucket.append(entry)
        }
        if let start { days.append(HydrationDay(start: start, entries: bucket)) }
        return days
    }

    /// The day `date` falls in, empty when nothing was drunk.
    func day(containing date: Date, calendar: Calendar) -> HydrationDay {
        let start = calendar.startOfDay(for: date)
        let entries = entries.filter { calendar.startOfDay(for: $0.date) == start }
        return HydrationDay(start: start, entries: entries)
    }

    /// Today and the `recentDays - 1` before it, unless the older ones are asked for.
    func history(
        now: Date, calendar: Calendar, recentDays: Int, showingOlder: Bool
    ) -> HydrationHistory {
        let all = days(calendar: calendar)
        guard !showingOlder else { return HydrationHistory(days: all, hasOlder: false) }
        let today = calendar.startOfDay(for: now)
        guard let oldest = calendar.date(byAdding: .day, value: -(recentDays - 1), to: today) else {
            return HydrationHistory(days: all, hasOlder: false)
        }
        let recent = all.filter { $0.start >= oldest }
        return HydrationHistory(days: recent, hasOlder: recent.count < all.count)
    }
}

extension HydrationLog {
    private struct Document: Encodable {
        let entries: [HydrationEntry]
    }

    /// One bad entry loses only itself, never the rest of the history.
    private struct LossyDocument: Decodable {
        struct Slot: Decodable {
            let entry: HydrationEntry?

            init(from decoder: Decoder) throws {
                entry = try? HydrationEntry(from: decoder)
            }
        }
        let entries: [Slot]
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Document(entries: entries))
    }

    /// Unreadable data is an empty log: a history file is a convenience, never a reason to fail.
    static func decode(_ data: Data) -> HydrationLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(LossyDocument.self, from: data) else {
            return HydrationLog()
        }
        return HydrationLog(entries: document.entries.compactMap(\.entry))
    }
}
