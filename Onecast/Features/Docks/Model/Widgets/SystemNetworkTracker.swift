import Foundation

/// Turns the 32-bit byte counters `getifaddrs` reports into rates and running totals.
struct SystemNetworkTracker: Sendable {
    struct Counters: Sendable, Equatable {
        let received: UInt32
        let sent: UInt32
    }

    /// Bytes per second.
    struct Throughput: Sendable, Equatable {
        var download: Double
        var upload: Double

        static let zero = Throughput(download: 0, upload: 0)
    }

    struct Traffic: Sendable, Equatable {
        var received: UInt64
        var sent: UInt64
    }

    /// A counter that moves backward by more than this wrapped too far to be real traffic.
    private static let plausibleWrap: UInt64 = 1 << 31

    private var last: [String: Counters] = [:]
    /// Bytes moved since each interface was first seen, wrap-corrected into 64 bits.
    private(set) var totals: [String: Traffic] = [:]

    init() {}

    /// Bytes between two readings: a wrap adds the counter's range, an implausible one is a reset.
    static func delta(from previous: UInt32, to current: UInt32) -> UInt64 {
        if current >= previous { return UInt64(current - previous) }
        let wrapped = UInt64(current) + (1 << 32) - UInt64(previous)
        return wrapped > plausibleWrap ? UInt64(current) : wrapped
    }

    /// Each interface's rate over `elapsed` seconds; one seen for the first time reads zero.
    mutating func advance(
        _ readings: [String: Counters], elapsed: TimeInterval
    ) -> [String: Throughput] {
        var rates: [String: Throughput] = [:]
        var traffic: [String: Traffic] = [:]
        for (name, counters) in readings {
            guard let previous = last[name] else {
                rates[name] = .zero
                traffic[name] = Traffic(received: 0, sent: 0)
                continue
            }
            let received = Self.delta(from: previous.received, to: counters.received)
            let sent = Self.delta(from: previous.sent, to: counters.sent)
            let seen = totals[name] ?? Traffic(received: 0, sent: 0)
            traffic[name] = Traffic(received: seen.received + received, sent: seen.sent + sent)
            rates[name] =
                elapsed > 0
                ? Throughput(download: Double(received) / elapsed, upload: Double(sent) / elapsed)
                : .zero
        }
        last = readings
        totals = traffic
        return rates
    }
}
