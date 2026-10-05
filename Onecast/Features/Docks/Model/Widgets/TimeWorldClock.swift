import Foundation

/// The zones a world clock shows, resolved from the cities and identifiers the user typed.
struct TimeWorldClock: Equatable, Sendable, Identifiable {
    static let limit = 4

    /// The IANA identifier.
    let id: String
    let label: String
    let zone: TimeZone

    /// Up to `limit` zones from comma-separated IANA ids or city names; misses and repeats drop.
    static func resolve(_ text: String) -> [TimeWorldClock] {
        var seen: Set<String> = []
        var clocks: [TimeWorldClock] = []
        for entry in text.split(whereSeparator: { ",;\n".contains($0) }) {
            guard let zone = zone(named: entry.trimmingCharacters(in: .whitespaces)),
                seen.insert(zone.identifier).inserted
            else { continue }
            clocks.append(TimeWorldClock(id: zone.identifier, label: label(for: zone), zone: zone))
            if clocks.count == limit { break }
        }
        return clocks
    }

    /// Whole days this zone's date is ahead of (positive) or behind the Mac's own date.
    func dayOffset(at date: Date, home: TimeZone) -> Int {
        Self.dayNumber(date, in: zone) - Self.dayNumber(date, in: home)
    }

    /// How far this zone's clock runs ahead of (positive) or behind the Mac's own, in seconds.
    func secondsAhead(at date: Date, home: TimeZone) -> Int {
        zone.secondsFromGMT(for: date) - home.secondsFromGMT(for: date)
    }

    private static func zone(named entry: String) -> TimeZone? {
        guard !entry.isEmpty else { return nil }
        let words = entry.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if let zone = TimeZone(identifier: entry) { return zone }
        if let identifier = identifiers[words.joined(separator: "_")] {
            return TimeZone(identifier: identifier)
        }
        return CalcTimeZone.zone(named: words)
    }

    /// So `europe/london` and `America/New York` name zones as readily as the exact identifier.
    private static let identifiers: [String: String] = Dictionary(
        TimeZone.knownTimeZoneIdentifiers.map { ($0.lowercased(), $0) },
        uniquingKeysWith: { first, _ in first })

    /// The city of an identifier, as the calculator labels it.
    private static func label(for zone: TimeZone) -> String {
        if zone.identifier == "GMT" || zone.identifier == "UTC" { return "UTC" }
        guard let city = zone.identifier.split(separator: "/").last else { return zone.identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    /// Days since the reference date of the zone's calendar date, so two zones subtract cleanly.
    private static func dayNumber(_ date: Date, in zone: TimeZone) -> Int {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? zone
        let midnight = utc.date(from: parts) ?? date
        return Int((midnight.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }
}
