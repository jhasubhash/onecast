import CoreFoundation
import Foundation
import IOKit.ps
import Observation

/// What the run-loop callback holds: the stream's end, which is safe to yield from anywhere.
private final class PowerSourceRelay: Sendable {
    let continuation: AsyncStream<Void>.Continuation

    init(_ continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }
}

private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<PowerSourceRelay>.fromOpaque(context).takeUnretainedValue().continuation.yield()
}

/// The battery's state, shared by every Battery tile; observed only while leased.
@MainActor
@Observable
final class SystemBatteryMonitor {
    /// Nil on a Mac with no battery, which the tile shows as AC power.
    private(set) var reading: SystemBatteryReading?
    private(set) var details = SystemBatteryDetails(.init())
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// False until the first read lands, so a tile never flashes "AC Power" while it loads.
    private(set) var hasRead = false

    @ObservationIgnored private var leases = 0
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var relayContext: UnsafeMutableRawPointer?

    /// An estimate drifts between power-source events, so it is also re-read on this cadence.
    private static let refreshInterval = Duration.seconds(60)

    func lease() -> SystemSamplerLease {
        leases += 1
        if leases == 1 { start() }
        return SystemSamplerLease { [self] in
            leases -= 1
            if leases == 0 { stop() }
        }
    }

    private func start() {
        let (changes, continuation) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let context = Unmanaged.passRetained(PowerSourceRelay(continuation)).toOpaque()
        if let created = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?
            .takeRetainedValue()
        {
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
            source = created
            relayContext = context
        } else {
            Unmanaged<PowerSourceRelay>.fromOpaque(context).release()
            continuation.finish()
        }
        changeTask = Task {
            for await _ in changes { await refresh() }
        }
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    private func stop() {
        changeTask?.cancel()
        refreshTask?.cancel()
        changeTask = nil
        refreshTask = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let relayContext { Unmanaged<PowerSourceRelay>.fromOpaque(relayContext).release() }
        relayContext = nil
        hasRead = false
    }

    private func refresh() async {
        let result = await Task.detached(priority: .utility) {
            (SystemBatteryProbe.reading(), SystemBatteryProbe.details())
        }.value
        guard leases > 0 else { return }
        reading = result.0
        details = result.1
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        hasRead = true
    }
}
