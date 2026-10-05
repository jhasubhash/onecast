import Foundation
import Observation

/// Interface throughput shared by every Network Activity tile; ticks only while leased.
@MainActor
@Observable
final class SystemNetworkSampler {
    nonisolated static let historyLength = 60

    struct RateHistory: Equatable {
        var download = SystemSeries(capacity: SystemNetworkSampler.historyLength)
        var upload = SystemSeries(capacity: SystemNetworkSampler.historyLength)
    }

    private(set) var sample = SystemNetworkSample.empty
    private(set) var history: [SystemNetworkSample.Scope: RateHistory] = [
        .primary: RateHistory(), .total: RateHistory(),
    ]
    private(set) var wifi: SystemNetworkProbe.WiFi?

    @ObservationIgnored private var leases = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let pacer = SystemPacer()
    @ObservationIgnored private var tracker = SystemNetworkTracker()
    @ObservationIgnored private var lastTick: ContinuousClock.Instant?

    /// CoreWLAN talks to a daemon, so Wi-Fi is asked about on every few ticks, not every one.
    private static let wifiRefreshTicks = 5

    func lease() -> SystemSamplerLease {
        leases += 1
        if leases == 1 { task = Task { await run() } }
        return SystemSamplerLease { [self] in
            leases -= 1
            if leases == 0 { stop() }
        }
    }

    func history(for scope: SystemNetworkSample.Scope) -> RateHistory {
        history[scope] ?? RateHistory()
    }

    private func stop() {
        task?.cancel()
        task = nil
        tracker = SystemNetworkTracker()
        lastTick = nil
        sample = .empty
        wifi = nil
        history = [.primary: RateHistory(), .total: RateHistory()]
    }

    private func run() async {
        var tick = 0
        while !Task.isCancelled {
            let reading = await Task.detached(priority: .utility) { SystemNetworkProbe.read() }.value
            if Task.isCancelled { return }
            apply(reading)
            if tick % Self.wifiRefreshTicks == 0 {
                wifi = await Task.detached(priority: .utility) { SystemNetworkProbe.wifi() }.value
            }
            tick += 1
            await pacer.wait(.seconds(1))
        }
    }

    private func apply(_ reading: SystemNetworkProbe.Reading) {
        let now = ContinuousClock.now
        let elapsed = lastTick.map { Self.seconds($0.duration(to: now)) } ?? 0
        lastTick = now
        let rates = tracker.advance(reading.counters, elapsed: elapsed)
        let interfaces = reading.counters.keys.sorted().map { name in
            SystemNetworkSample.Interface(
                name: name, kind: .classify(name), isUp: reading.links[name]?.isUp ?? false,
                address: reading.links[name]?.address, throughput: rates[name] ?? .zero,
                traffic: tracker.totals[name] ?? SystemNetworkTracker.Traffic(received: 0, sent: 0))
        }
        sample = SystemNetworkSample(interfaces: interfaces, primaryName: reading.primaryName)
        guard elapsed > 0 else { return }
        for scope in SystemNetworkSample.Scope.allCases {
            let rate = sample.throughput(for: scope)
            history[scope, default: RateHistory()].download.append(rate.download)
            history[scope, default: RateHistory()].upload.append(rate.upload)
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
