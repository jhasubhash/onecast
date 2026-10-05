import Foundation
import Observation

/// CPU, memory and volume readings shared by every System Activity tile; ticks only while leased.
@MainActor
@Observable
final class SystemActivitySampler {
    static let historyLength = 60

    private(set) var cpu: SystemCPUUsage?
    private(set) var cpuHistory = SystemSeries(capacity: historyLength)
    private(set) var memory: SystemMemoryUsage?
    private(set) var memoryHistory = SystemSeries(capacity: historyLength)
    private(set) var loadAverages: [Double] = []
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var volumes: [SystemStorage.Volume] = []
    private(set) var bootDate: Date?

    @ObservationIgnored private var leases = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let pacer = SystemPacer()
    @ObservationIgnored private var previousTicks: [SystemCPUUsage.Ticks] = []
    @ObservationIgnored private var pressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var observers: [NotificationToken] = []

    /// Capacity moves slowly, so volumes refresh every few ticks rather than every one.
    private static let volumeRefreshTicks = 30
    /// The first delta needs a second snapshot, so it is taken soon rather than a full tick on.
    private static let firstDeltaDelay = Duration.milliseconds(250)

    var uptime: TimeInterval { bootDate.map { Date().timeIntervalSince($0) } ?? 0 }

    func lease() -> SystemSamplerLease {
        leases += 1
        if leases == 1 { start() }
        return SystemSamplerLease { [self] in
            leases -= 1
            if leases == 0 { stop() }
        }
    }

    private func start() {
        thermalState = ProcessInfo.processInfo.thermalState
        observers = [
            NotificationToken(
                NotificationCenter.default.addObserver(
                    forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.thermalState = ProcessInfo.processInfo.thermalState }
                }, center: .default)
        ]
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.pacer.wake() }
        }
        source.resume()
        pressureSource = source
        task = Task { await run() }
    }

    private func stop() {
        task?.cancel()
        task = nil
        pressureSource?.cancel()
        pressureSource = nil
        observers = []
        previousTicks = []
        cpu = nil
        memory = nil
        cpuHistory = SystemSeries(capacity: Self.historyLength)
        memoryHistory = SystemSeries(capacity: Self.historyLength)
    }

    private func run() async {
        var tick = 0
        while !Task.isCancelled {
            let reading = await Task.detached(priority: .utility) { SystemActivityProbe.read() }.value
            if Task.isCancelled { return }
            apply(reading)
            if tick % Self.volumeRefreshTicks == 0 {
                volumes = await Task.detached(priority: .utility) { SystemStorageProbe.volumes() }.value
            }
            tick += 1
            await pacer.wait(tick == 1 ? Self.firstDeltaDelay : .seconds(1))
        }
    }

    private func apply(_ reading: SystemActivityProbe.Reading) {
        if let usage = SystemCPUUsage.between(previousTicks, reading.ticks) {
            cpu = usage
            cpuHistory.append(usage.overall)
        }
        previousTicks = reading.ticks
        if let memory = reading.memory {
            self.memory = memory
            memoryHistory.append(memory.usedFraction)
        }
        loadAverages = reading.loadAverages
        bootDate = reading.bootDate
    }
}
