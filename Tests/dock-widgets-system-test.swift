import Foundation

@main
@MainActor
struct DockWidgetsSystemTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        seriesKeepsTheNewestSamples()
        seriesPadsAndScalesForTheSparkline()
        niceCeilingStepsUpInRoundNumbers()
        formatPrintsDecimalUnits()
        formatPrintsDurations()
        cpuUsageIsTheBusyShareOfTheTicksBetweenSnapshots()
        cpuUsageSurvivesCounterWrap()
        cpuUsageRejectsUnrelatedSnapshots()
        memoryFollowsActivityMonitorGrouping()
        memoryNeverOverflowsTotal()
        pressureMapsKernelLevels()
        storageOrdersAndRanksStably()
        scanRootsResolveAgainstTheInjectedHome()
        counterDeltaHandlesWrapAndReset()
        trackerReportsRatesAndAccumulatesTotals()
        trackerRebaselinesAReturningInterface()
        interfacesAreClassifiedByName()
        samplePrefersTheDefaultRouteAndSumsOnlyPhysicalLinks()
        batteryReadingResolvesStatusAndEstimate()
        batteryReadingRejectsASourceWithoutCapacity()
        batterySymbolFollowsChargeAndBolt()
        batteryTileTitleIsShorterThanTheStatus()
        loadLevelGradesAFraction()
        batteryDetailsComputeHealthFromTheRightCapacity()
        nowPlayingParsesATrack()
        nowPlayingRejectsMalformedAnswers()
        nowPlayingSkipStaysInsideTheTrack()
        nowPlayingPicksTheMostActiveSource()
        nowPlayingPollsFasterWhilePlaying()
        nowPlayingSettingsReadDefaultsAndValues()
        nowPlayingLayoutFitsWhatThereIsRoomFor()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Series

    static func seriesKeepsTheNewestSamples() {
        var series = SystemSeries(capacity: 3)
        for value in [1.0, 2, 3, 4, 5] { series.append(value) }
        expect(series.values == [3, 4, 5], "a full series drops its oldest samples")
        expect(series.latest == 5 && series.peak == 5, "latest and peak read the window")
        series.append(-4)
        series.append(.nan)
        expect(series.values == [5, 0, 0], "a negative or non-finite sample reads as zero")
        expect(SystemSeries(capacity: 1).capacity == 2, "a series always holds at least two points")
    }

    static func seriesPadsAndScalesForTheSparkline() {
        var series = SystemSeries(capacity: 4)
        series.append(50)
        series.append(100)
        expect(series.normalized(ceiling: 100) == [0.5, 1], "a young series holds only the samples it has")
        series.append(300)
        expect(series.normalized(ceiling: 100) == [0.5, 1, 1], "a sample over the ceiling is held to 1")
        expect(series.normalized(ceiling: 0) == [0, 0, 0], "no ceiling draws a flat line")
    }

    static func niceCeilingStepsUpInRoundNumbers() {
        expect(SystemSeries.niceCeiling(for: 0, floor: 1_000) == 1_000, "an idle link sits at the floor")
        expect(SystemSeries.niceCeiling(for: 3_200_000, floor: 1_000) == 5_000_000, "3.2 MB/s rounds to 5")
        expect(SystemSeries.niceCeiling(for: 1_500_000, floor: 1_000) == 2_000_000, "1.5 MB/s rounds to 2")
        expect(SystemSeries.niceCeiling(for: 800_000, floor: 1_000) == 1_000_000, "headroom still lands on 1 MB/s")
        expect(SystemSeries.niceCeiling(for: .infinity, floor: 1_000) == 1_000, "infinity falls back to the floor")
    }

    // MARK: - Format

    static func formatPrintsDecimalUnits() {
        expect(SystemFormat.bytes(0) == "0 B", "zero bytes")
        expect(SystemFormat.bytes(999) == "999 B", "bytes stay whole")
        expect(SystemFormat.bytes(1_500) == "1.5 KB", "one decimal under 100")
        expect(SystemFormat.bytes(250_000_000) == "250 MB", "whole numbers from 100")
        expect(SystemFormat.bytes(999_960) == "1.0 MB", "a value that rounds to 1000 moves up a unit")
        expect(SystemFormat.rate(1_250_000) == "1.3 MB/s" || SystemFormat.rate(1_250_000) == "1.2 MB/s", "a rate carries /s")
        expect(SystemFormat.rate(-5) == "0 B/s", "a negative rate reads as zero")
        expect(SystemFormat.byteQuantity(2_000_000_000) == SystemFormat.Quantity(value: "2.0", unit: "GB"), "quantity splits value and unit")
        expect(SystemFormat.percent(0.426) == "43%", "percent rounds")
        expect(SystemFormat.percent(1.4) == "100%" && SystemFormat.percent(-1) == "0%", "percent is held to 0...100")
        expect(SystemFormat.percentValue(.nan) == 0, "a NaN fraction reads as zero")
    }

    static func formatPrintsDurations() {
        expect(SystemFormat.uptime(seconds: 90_000) == "1d 1h", "uptime past a day")
        expect(SystemFormat.uptime(seconds: 5_400) == "1h 30m", "uptime past an hour")
        expect(SystemFormat.uptime(seconds: 59) == "0m", "uptime under a minute")
        expect(SystemFormat.hoursAndMinutes(minutes: 135) == "2:15", "battery estimate")
        expect(SystemFormat.hoursAndMinutes(minutes: 5) == "0:05", "battery estimate pads minutes")
        expect(SystemFormat.clock(seconds: 65) == "1:05", "playback position")
        expect(SystemFormat.clock(seconds: 3_723) == "1:02:03", "playback position past an hour")
        expect(SystemFormat.clock(seconds: .nan) == "0:00", "a NaN position reads as zero")
    }

    // MARK: - CPU

    typealias Ticks = SystemCPUUsage.Ticks

    static func cpuUsageIsTheBusyShareOfTheTicksBetweenSnapshots() {
        let before = [Ticks(user: 100, system: 50, idle: 800, nice: 0), Ticks(user: 0, system: 0, idle: 100, nice: 0)]
        let after = [Ticks(user: 150, system: 70, idle: 880, nice: 0), Ticks(user: 0, system: 0, idle: 200, nice: 0)]
        guard let usage = SystemCPUUsage.between(before, after) else {
            return expect(false, "two related snapshots yield a usage")
        }
        expect(usage.cores == [70.0 / 150.0, 0], "per-core busy share")
        expect(abs(usage.overall - 70.0 / 250.0) < 1e-9, "overall is weighted by ticks, not averaged")
        expect(abs(usage.user - 50.0 / 250.0) < 1e-9 && abs(usage.system - 20.0 / 250.0) < 1e-9, "user and system split")
    }

    static func cpuUsageSurvivesCounterWrap() {
        let before = [Ticks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)]
        let after = [Ticks(user: 10, system: 0, idle: 20, nice: 0)]
        let usage = SystemCPUUsage.between(before, after)
        expect(usage?.cores == [0.5], "a wrapped 32-bit counter still yields its true delta")
    }

    static func cpuUsageRejectsUnrelatedSnapshots() {
        let one = [Ticks(user: 1, system: 1, idle: 1, nice: 1)]
        expect(SystemCPUUsage.between(one, one + one) == nil, "a different core count is not comparable")
        expect(SystemCPUUsage.between(one, one) == nil, "no elapsed ticks is not a reading")
        expect(SystemCPUUsage.between([], []) == nil, "no cores is not a reading")
    }

    // MARK: - Memory

    static func memoryFollowsActivityMonitorGrouping() {
        let pages = SystemMemoryUsage.Pages(
            free: 100, wired: 200, compressed: 50, purgeable: 20, internalPages: 320, external: 80)
        let memory = SystemMemoryUsage(pages: pages, pageSize: 10, total: 10_000)
        expect(memory.app == 3_000, "app memory is internal pages minus purgeable")
        expect(memory.wired == 2_000 && memory.compressed == 500, "wired and compressed")
        expect(memory.cached == 1_000, "cached is file-backed plus purgeable")
        expect(memory.used == 5_500, "used is app + wired + compressed")
        expect(memory.free == 1_000, "free is the free pages")
        expect(abs(memory.usedFraction - 0.55) < 1e-9, "used fraction")
    }

    static func memoryNeverOverflowsTotal() {
        let pages = SystemMemoryUsage.Pages(
            free: 900, wired: 500, compressed: 500, purgeable: 0, internalPages: 500, external: 500)
        let memory = SystemMemoryUsage(pages: pages, pageSize: 10, total: 1_000)
        expect(memory.used <= 1_000 && memory.usedFraction <= 1, "counters that exceed RAM are held to it")
        expect(memory.free == 0, "no free memory is left once the groups fill RAM")
        let odd = SystemMemoryUsage.Pages(
            free: 0, wired: 0, compressed: 0, purgeable: 50, internalPages: 10, external: 0)
        expect(SystemMemoryUsage(pages: odd, pageSize: 1, total: 100).app == 0, "purgeable above internal cannot underflow")
    }

    static func pressureMapsKernelLevels() {
        expect(SystemMemoryUsage.Pressure(kernelLevel: 1) == .normal, "level 1 is normal")
        expect(SystemMemoryUsage.Pressure(kernelLevel: 2) == .warning, "level 2 is warning")
        expect(SystemMemoryUsage.Pressure(kernelLevel: 4) == .critical, "level 4 is critical")
        expect(SystemMemoryUsage.Pressure(kernelLevel: 0) == .normal, "an unknown level is normal")
        expect(SystemMemoryUsage.Pressure.warning < .critical, "pressure orders by severity")
    }

    // MARK: - Storage

    static func storageOrdersAndRanksStably() {
        typealias Volume = SystemStorage.Volume
        let volumes = [
            Volume(name: "Zed", path: "/Volumes/Zed", total: 100, available: 50, isRoot: false),
            Volume(name: "Macintosh HD", path: "/", total: 100, available: 25, isRoot: true),
            Volume(name: "Alpha", path: "/Volumes/Alpha", total: 100, available: 90, isRoot: false),
        ]
        expect(SystemStorage.ordered(volumes).map(\.name) == ["Macintosh HD", "Alpha", "Zed"], "root first, then by name")
        expect(volumes[1].used == 75 && volumes[1].usedFraction == 0.75, "used is total minus available")
        expect(Volume(name: "x", path: "/x", total: 10, available: 99, isRoot: false).used == 0, "available above total cannot underflow")

        typealias Entry = SystemStorage.Entry
        let entries = [
            Entry(name: "b", path: "/b", bytes: 10, isDirectory: true),
            Entry(name: "a", path: "/a", bytes: 10, isDirectory: true),
            Entry(name: "big", path: "/big", bytes: 90, isDirectory: false),
        ]
        expect(SystemStorage.ranked(entries).map(\.name) == ["big", "a", "b"], "largest first, ties by name")
        expect(SystemStorage.share(of: entries[2], in: 100) == 0.9, "share of the scanned total")
        expect(SystemStorage.share(of: entries[2], in: 0) == 0, "an empty total has no share")
    }

    static func scanRootsResolveAgainstTheInjectedHome() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        expect(SystemStorage.ScanRoot.home.url(home: home).path == "/Users/someone", "home is the injected home")
        expect(SystemStorage.ScanRoot.applications.url(home: home).path == "/Applications", "applications is fixed")
        expect(SystemStorage.ScanRoot.library.url(home: home).path == "/Users/someone/Library", "library sits in the home")
    }

    // MARK: - Network

    typealias Counters = SystemNetworkTracker.Counters

    static func counterDeltaHandlesWrapAndReset() {
        typealias Tracker = SystemNetworkTracker
        expect(Tracker.delta(from: 100, to: 250) == 150, "a forward step is its difference")
        expect(Tracker.delta(from: UInt32.max - 9, to: 10) == 20, "a small wrap adds the counter range")
        expect(Tracker.delta(from: 1_000_000_000, to: 500) == 500, "an implausible wrap is an interface reset")
    }

    static func trackerReportsRatesAndAccumulatesTotals() {
        var tracker = SystemNetworkTracker()
        let first = tracker.advance(["en0": Counters(received: 1_000, sent: 500)], elapsed: 1)
        expect(first["en0"] == .zero, "an interface seen for the first time reads zero")
        let second = tracker.advance(["en0": Counters(received: 3_000, sent: 700)], elapsed: 2)
        expect(second["en0"] == SystemNetworkTracker.Throughput(download: 1_000, upload: 100), "rate is bytes over elapsed")
        _ = tracker.advance(["en0": Counters(received: 4_000, sent: 700)], elapsed: 1)
        expect(tracker.totals["en0"] == SystemNetworkTracker.Traffic(received: 3_000, sent: 200), "totals accumulate across ticks")
        let idle = tracker.advance(["en0": Counters(received: 9, sent: 9)], elapsed: 0)
        expect(idle["en0"] == .zero, "a zero interval cannot divide")
    }

    static func trackerRebaselinesAReturningInterface() {
        var tracker = SystemNetworkTracker()
        _ = tracker.advance(["utun3": Counters(received: 10, sent: 10)], elapsed: 1)
        _ = tracker.advance([:], elapsed: 1)
        expect(tracker.totals.isEmpty, "a vanished interface drops its totals")
        let back = tracker.advance(["utun3": Counters(received: 5_000_000, sent: 5_000_000)], elapsed: 1)
        expect(back["utun3"] == .zero, "a returning interface is baselined, not counted from zero")
    }

    static func interfacesAreClassifiedByName() {
        typealias Kind = SystemNetworkInterfaceKind
        expect(Kind.classify("en0") == .ethernetOrWiFi && Kind.classify("en12") == .ethernetOrWiFi, "enN is wired or Wi-Fi")
        expect(Kind.classify("enc0") == .other, "a name that merely starts with en is not")
        expect(Kind.classify("lo0") == .loopback, "lo0 is loopback")
        expect(Kind.classify("utun4") == .tunnel && Kind.classify("ipsec0") == .tunnel, "VPN interfaces are tunnels")
        expect(Kind.classify("pdp_ip0") == .cellular, "pdp_ip is cellular")
        expect(Kind.classify("bridge0") == .bridge, "bridge")
        expect(Kind.classify("awdl0") == .peerToPeer && Kind.classify("llw0") == .peerToPeer, "peer to peer")
        expect(Kind.ethernetOrWiFi.countsTowardTotal && Kind.cellular.countsTowardTotal, "physical links count")
        expect(!Kind.tunnel.countsTowardTotal && !Kind.bridge.countsTowardTotal && !Kind.loopback.countsTowardTotal, "overlays do not")
    }

    static func samplePrefersTheDefaultRouteAndSumsOnlyPhysicalLinks() {
        typealias Interface = SystemNetworkSample.Interface
        func make(_ name: String, down: Double, up: Double, isUp: Bool = true) -> Interface {
            Interface(
                name: name, kind: SystemNetworkInterfaceKind.classify(name), isUp: isUp, address: nil,
                throughput: .init(download: down, upload: up), traffic: .init(received: 0, sent: 0))
        }
        let interfaces = [
            make("en0", down: 100, up: 10), make("en1", down: 400, up: 0),
            make("utun3", down: 100, up: 10), make("lo0", down: 999, up: 999),
        ]
        let routed = SystemNetworkSample(interfaces: interfaces, primaryName: "en0")
        expect(routed.primary?.name == "en0", "the default-route interface is primary")
        expect(routed.total == SystemNetworkTracker.Throughput(download: 500, upload: 10), "total skips tunnels and loopback")
        expect(routed.throughput(for: .primary).download == 100 && routed.throughput(for: .total).download == 500, "scope picks the rate")
        let guess = SystemNetworkSample(interfaces: interfaces, primaryName: nil)
        expect(guess.primary?.name == "en1", "with no route the busiest physical link stands in")
        let down = SystemNetworkSample(interfaces: [make("en0", down: 1, up: 1, isUp: false)], primaryName: "en0")
        expect(down.primary == nil, "a link that is down is never primary")
        expect(SystemNetworkSample.empty.throughput(for: .primary) == .zero, "no interfaces, no traffic")
        func link(_ name: String, address: String?, bytes: UInt64) -> Interface {
            Interface(
                name: name, kind: SystemNetworkInterfaceKind.classify(name), isUp: true, address: address,
                throughput: .zero, traffic: .init(received: bytes, sent: 0))
        }
        let listed = SystemNetworkSample(
            interfaces: [
                link("en0", address: "10.0.0.2", bytes: 0), link("en5", address: nil, bytes: 0),
                link("utun3", address: nil, bytes: 9), link("lo0", address: "127.0.0.1", bytes: 9),
            ], primaryName: "en0"
        ).visibleInterfaces
        expect(listed.map(\.name) == ["en0", "utun3"], "the list keeps addressed or busy links, never idle ones or loopback")
    }

    // MARK: - Battery

    typealias Raw = SystemBatteryReading.Raw

    static func raw(
        _ current: Int, of maximum: Int = 100, charging: Bool = false, charged: Bool = false,
        adapter: Bool = false, empty: Int? = nil, full: Int? = nil
    ) -> Raw {
        Raw(
            currentCapacity: current, maximumCapacity: maximum, isCharging: charging, isCharged: charged,
            onAdapter: adapter, minutesToEmpty: empty, minutesToFull: full)
    }

    static func batteryReadingResolvesStatusAndEstimate() {
        let draining = SystemBatteryReading(raw(42, empty: 135))
        expect(draining?.status == .discharging && draining?.percent == 42, "unplugged drains")
        expect(draining?.timeText == "2:15 remaining", "time to empty")
        let charging = SystemBatteryReading(raw(60, charging: true, adapter: true, empty: 10, full: 40))
        expect(charging?.status == .charging && charging?.timeText == "0:40 until full", "time to full while charging")
        expect(SystemBatteryReading(raw(50, empty: -1))?.timeText == nil, "an unknown estimate prints nothing")
        expect(SystemBatteryReading(raw(100, charged: true, adapter: true))?.status == .charged, "charged")
        expect(SystemBatteryReading(raw(80, adapter: true))?.status == .pluggedIn, "plugged in but not charging")
        expect(SystemBatteryReading(raw(80, adapter: true))?.isOnAdapter == true, "an adapter state is on the adapter")
        expect(SystemBatteryReading(raw(15))?.isLow == true, "low while draining under 20%")
        expect(SystemBatteryReading(raw(15, charging: true, adapter: true))?.isLow == false, "never low on a charger")
        expect(SystemBatteryReading(raw(4_400, of: 8_800))?.percent == 50, "capacity is a ratio, not assumed 100")
    }

    static func batteryReadingRejectsASourceWithoutCapacity() {
        expect(SystemBatteryReading(raw(5, of: 0)) == nil, "no maximum capacity is no battery")
        expect(SystemBatteryReading(raw(250, of: 100))?.percent == 100, "an overfull reading is held to 100")
    }

    static func batterySymbolFollowsChargeAndBolt() {
        expect(SystemBatteryReading(raw(5))?.symbol == "battery.0percent", "empty glyph")
        expect(SystemBatteryReading(raw(30))?.symbol == "battery.25percent", "quarter glyph")
        expect(SystemBatteryReading(raw(55))?.symbol == "battery.50percent", "half glyph")
        expect(SystemBatteryReading(raw(80))?.symbol == "battery.75percent", "three quarter glyph")
        expect(SystemBatteryReading(raw(95))?.symbol == "battery.100percent", "full glyph")
        expect(SystemBatteryReading(raw(55, charging: true, adapter: true))?.symbol == "battery.50percent.bolt", "a charging pack gains a bolt")
    }

    static func batteryDetailsComputeHealthFromTheRightCapacity() {
        typealias Details = SystemBatteryDetails
        let silicon = Details(Details.Raw(designCapacity: 8_579, nominalChargeCapacity: 8_944, legacyMaxCapacity: 100, cycleCount: 105, adapterWatts: 90))
        expect(silicon.healthPercent == 100, "a pack above its design capacity reads 100%")
        expect(silicon.cycleCount == 105 && silicon.adapterWatts == 90, "cycles and adapter pass through")
        let worn = Details(Details.Raw(designCapacity: 8_000, nominalChargeCapacity: 6_800))
        expect(worn.healthPercent == 85, "health is nominal over design")
        let intel = Details(Details.Raw(designCapacity: 6_000, legacyMaxCapacity: 5_400))
        expect(intel.healthPercent == 90, "an Intel pack's MaxCapacity is mAh")
        let percentOnly = Details(Details.Raw(designCapacity: 6_000, legacyMaxCapacity: 100))
        expect(percentOnly.healthPercent == nil, "a MaxCapacity of 100 is a percentage, not a capacity")
        let temperature = Details(Details.Raw(temperature: 3_050, voltageMillivolts: 12_247))
        expect(temperature.temperatureCelsius == 30.5 && temperature.voltage == 12.247, "temperature and voltage scale")
        expect(Details(Details.Raw()).isEmpty, "a registry with nothing readable is empty")
        expect(Details(Details.Raw(adapterWatts: 0)).adapterWatts == nil, "no adapter reads as nil")
    }

    static func batteryTileTitleIsShorterThanTheStatus() {
        expect(SystemBatteryReading(raw(80, adapter: true))?.tileTitle == "Plugged in", "plugged in, short")
        expect(SystemBatteryReading(raw(80, adapter: true))?.statusTitle == "Plugged in, not charging", "plugged in, long")
        expect(SystemBatteryReading(raw(80, charging: true, adapter: true))?.tileTitle == "Charging", "charging")
        expect(SystemBatteryReading(raw(100, charged: true, adapter: true))?.tileTitle == "Charged", "charged")
        expect(SystemBatteryReading(raw(50))?.tileTitle == "On battery", "on battery")
    }

    static func loadLevelGradesAFraction() {
        expect(SystemLoadLevel(fraction: 0.2) == .calm, "a quiet system is calm")
        expect(SystemLoadLevel(fraction: SystemLoadLevel.busyThreshold) == .busy, "the busy threshold is inclusive")
        expect(SystemLoadLevel(fraction: 0.84) == .busy, "just under saturated is busy")
        expect(SystemLoadLevel(fraction: SystemLoadLevel.saturatedThreshold) == .saturated, "the saturated threshold is inclusive")
        expect(SystemLoadLevel(fraction: 7) == .saturated, "an over-range load is saturated")
        expect(SystemActivityMetric(rawValue: "memory") == .memory && SystemActivityMetric(rawValue: "gpu") == nil, "metrics round-trip by name")
    }

    // MARK: - Now Playing

    typealias NowPlaying = SystemNowPlaying

    static func nowPlayingParsesATrack() {
        let fields = ["playing", "Song", "Artist", "Album", "12500", "200000", "spotify:track:1", "https://i.scdn.co/a.jpg"]
        guard case .track(let track) = NowPlaying.parse(source: .spotify, fields: fields) else {
            return expect(false, "a playing answer parses to a track")
        }
        expect(track.title == "Song" && track.artist == "Artist" && track.album == "Album", "text fields")
        expect(track.position == 12.5 && track.duration == 200 && track.isPlaying, "milliseconds become seconds")
        expect(track.progress == 12.5 / 200, "progress is position over duration")
        expect(track.artworkURL?.absoluteString == "https://i.scdn.co/a.jpg", "an https artwork URL is kept")
        expect(track.artworkKey == "spotify:spotify:track:1", "artwork is keyed by source and id")

        let insecure = NowPlaying.parse(source: .spotify, fields: Array(fields.dropLast()) + ["http://example.com/a.jpg"])
        expect(insecure.track?.artworkURL == nil, "an http artwork URL is dropped")
        let music = NowPlaying.parse(source: .music, fields: ["paused", "T", "A", "B", "0", "0", ""])
        expect(music.track?.identity == "T|A|B", "a missing id falls back to the text")
        expect(music.track?.progress == 0 && music.track?.isPlaying == false, "a stream with no length has no progress")
        let past = NowPlaying.parse(source: .music, fields: ["playing", "T", "A", "B", "999000", "60000", "id"])
        expect(past.track?.position == 60, "a position past the end is held to the duration")
        expect(NowPlaying.parse(source: .music, fields: ["closed"]) == .closed, "closed")
        expect(NowPlaying.parse(source: .music, fields: ["stopped"]) == .stopped, "stopped")
    }

    static func nowPlayingRejectsMalformedAnswers() {
        expect(NowPlaying.parse(source: .music, fields: []) == .failed, "an empty answer failed")
        expect(NowPlaying.parse(source: .music, fields: ["playing", "T"]) == .failed, "a short answer failed")
        expect(NowPlaying.parse(source: .music, fields: ["playing", "T", "A", "B", "x", "y", "id"]) == .failed, "non-numeric times failed")
        expect(NowPlaying.parse(source: .music, fields: ["fast forwarding"]) == .stopped, "an unknown state is not a track")
    }

    static func nowPlayingSkipStaysInsideTheTrack() {
        expect(NowPlaying.skipTarget(position: 50, by: 15, duration: 200) == 65, "a forward skip")
        expect(NowPlaying.skipTarget(position: 5, by: -15, duration: 200) == 0, "a back skip stops at the start")
        expect(NowPlaying.skipTarget(position: 195, by: 30, duration: 200) == 199, "a forward skip never reaches the next track")
        expect(NowPlaying.skipTarget(position: 10, by: -30, duration: 0) == 0, "a stream with no length still clamps at zero")
    }

    static func nowPlayingPicksTheMostActiveSource() {
        func track(_ source: NowPlaying.Source, _ state: NowPlaying.PlayerState) -> NowPlaying.Status {
            .track(NowPlaying.Track(source: source, state: state, title: "t", artist: "a", album: "b", position: 0, duration: 10, artworkURL: nil, identity: "1"))
        }
        let both = [NowPlaying.Source.spotify: track(.spotify, .paused), .music: track(.music, .playing)]
        expect(NowPlaying.active(both, previous: .spotify)?.source == .music, "a playing source beats a paused one")
        let tied = [NowPlaying.Source.spotify: track(.spotify, .paused), .music: track(.music, .paused)]
        expect(NowPlaying.active(tied, previous: .music)?.source == .music, "a tie keeps the source that was showing")
        expect(NowPlaying.active(tied, previous: nil)?.source == .spotify, "with no history a tie goes to the earlier source")
        expect(NowPlaying.active([.spotify: .closed, .music: .closed], previous: nil) == nil, "all closed shows nothing")
        let denied = [NowPlaying.Source.spotify: NowPlaying.Status.stopped, .music: .denied]
        expect(NowPlaying.active(denied, previous: nil)?.status == .denied, "a permission problem outranks an idle player")
        expect(NowPlaying.active([.spotify: .closed, .music: .stopped], previous: .spotify)?.source == .music, "a closed source is never active")
    }

    static func nowPlayingPollsFasterWhilePlaying() {
        func status(_ state: NowPlaying.PlayerState) -> NowPlaying.Status {
            .track(NowPlaying.Track(source: .music, state: state, title: "", artist: "", album: "", position: 0, duration: 1, artworkURL: nil, identity: "x"))
        }
        expect(NowPlaying.pollInterval(for: status(.playing)) == 1, "playing polls every second")
        expect(NowPlaying.pollInterval(for: status(.paused)) == 5, "paused polls slowly")
        expect(NowPlaying.pollInterval(for: .stopped) == 5 && NowPlaying.pollInterval(for: .denied) == 5, "idle polls slowly")
        expect(NowPlaying.pollInterval(for: .closed) == nil, "a closed player is never polled")
    }

    static func nowPlayingSettingsReadDefaultsAndValues() {
        let defaults = NowPlaying.Settings(value: { _ in nil })
        expect(defaults.sources == [.spotify, .music] && defaults.layout == .mini, "defaults: both sources, mini")
        expect(defaults.showsPreviousNext && !defaults.skipsEnabled && !defaults.hidesWhenClosed, "defaults: prev/next, no skip, no hiding")
        let values: [String: Any] = ["spotify": false, "music": true, "layout": "full", "showsPreviousNext": false, "skipSeconds": "30", "hidesWhenClosed": true]
        let set = NowPlaying.Settings(value: { values[$0] })
        expect(set.sources == [.music] && set.layout == .full, "explicit sources and layout")
        expect(!set.showsPreviousNext && set.skipSeconds == 30 && set.hidesWhenClosed, "explicit toggles")
        let bad: [String: Any] = ["layout": "huge", "skipSeconds": "7"]
        let fallback = NowPlaying.Settings(value: { bad[$0] })
        expect(fallback.layout == .mini && fallback.skipSeconds == 0, "malformed values fall back to the default")
    }

    static func nowPlayingLayoutFitsWhatThereIsRoomFor() {
        func settings(_ layout: String = "mini", previousNext: Bool = true, skip: String = "0") -> NowPlaying.Settings {
            let values: [String: Any] = ["layout": layout, "showsPreviousNext": previousNext, "skipSeconds": skip]
            return NowPlaying.Settings(value: { values[$0] })
        }
        func resolve(_ length: Double, _ thickness: Double, vertical: Bool = false, _ settings: NowPlaying.Settings) -> NowPlaying.TileLayout {
            NowPlaying.TileLayout.resolve(length: length, thickness: thickness, isVertical: vertical, settings: settings, inset: 4, control: 24)
        }
        let compact = resolve(60, 60, settings())
        expect(compact.controls.isEmpty && !compact.showsText && compact.artworkSide == 52, "one tile is artwork only")
        expect(resolve(60, 60, settings("full")).showsProgress, "a full compact tile still draws its progress line")
        expect(!compact.showsProgress, "a mini compact tile has no progress line")

        let wide = resolve(124, 60, settings())
        expect(wide.showsText && wide.controls.isEmpty, "a wide tile spends its room on text before controls")
        expect(wide.artworkTogglesPlayback, "with no room for a button, the artwork plays and pauses")
        let roomy = resolve(244, 60, settings())
        expect(roomy.controls == [.previous, .playPause, .next], "an expanded tile adds previous and next")
        expect(!roomy.showsProgress, "mini never draws progress")
        let fullRoomy = resolve(244, 80, settings("full", skip: "15"))
        expect(fullRoomy.showsProgress, "a full layout with height draws progress")
        expect(fullRoomy.controls == [.previous, .playPause, .next], "a full layout keeps the transport that fits")
        expect(resolve(244, 60, settings(previousNext: false)).controls == [.playPause], "previous and next can be switched off")
        expect(resolve(400, 60, settings(skip: "15")).controls == [.skipBack, .previous, .playPause, .next, .skipForward], "skip buttons flank the transport when there is room")
        expect(resolve(400, 60, settings(previousNext: false, skip: "15")).controls == [.skipBack, .playPause, .skipForward], "skip works without previous and next")

        let tightWide = resolve(100, 48, settings("full"))
        expect(!tightWide.showsProgress, "a thin tile has no room for a progress bar")
        let squeezed = resolve(80, 48, settings())
        expect(!squeezed.showsText && squeezed.controls == [.playPause], "when text cannot fit, the control wins over it")
        expect(!squeezed.artworkTogglesPlayback && !roomy.artworkTogglesPlayback, "a real play button leaves the artwork alone")

        let side = resolve(124, 60, vertical: true, settings())
        expect(side.showsText && side.controls.isEmpty, "a side dock lays a wide tile out vertically, text first")
        let tallSide = resolve(244, 100, vertical: true, settings(skip: "10"))
        expect(tallSide.controls == [.previous, .playPause, .next], "a row holds only as many controls as the tile is wide")
    }
}
