import Foundation

/// The slow-moving facts about the battery pack, read from the AppleSmartBattery registry entry.
struct SystemBatteryDetails: Sendable, Equatable {
    /// The registry's own numbers; each is nil when this Mac does not publish it.
    struct Raw: Sendable, Equatable {
        var designCapacity: Int?
        /// `NominalChargeCapacity`, the figure System Settings calls Maximum Capacity.
        var nominalChargeCapacity: Int?
        /// Older Macs publish the pack's current ceiling here, in mAh.
        var appleRawMaxCapacity: Int?
        /// Apple Silicon reports 100 here; an Intel pack reports mAh.
        var legacyMaxCapacity: Int?
        var cycleCount: Int?
        /// Hundredths of a degree Celsius.
        var temperature: Int?
        var voltageMillivolts: Int?
        var adapterWatts: Int?
    }

    /// A legacy ceiling at or under this is a percentage, not milliamp-hours.
    private static let percentCeiling = 100

    /// Capacity against what the pack was built for, whole percent, held to 100.
    let healthPercent: Int?
    let cycleCount: Int?
    let temperatureCelsius: Double?
    let voltage: Double?
    let adapterWatts: Int?

    init(_ raw: Raw) {
        let maximum =
            [raw.nominalChargeCapacity, raw.appleRawMaxCapacity]
            .compactMap { $0 }.first { $0 > 0 }
            ?? raw.legacyMaxCapacity.flatMap { $0 > Self.percentCeiling ? $0 : nil }
        if let design = raw.designCapacity, design > 0, let maximum {
            healthPercent = min(Int((Double(maximum) / Double(design) * 100).rounded()), 100)
        } else {
            healthPercent = nil
        }
        cycleCount = raw.cycleCount
        temperatureCelsius = raw.temperature.flatMap { $0 > 0 ? Double($0) / 100 : nil }
        voltage = raw.voltageMillivolts.flatMap { $0 > 0 ? Double($0) / 1000 : nil }
        adapterWatts = raw.adapterWatts.flatMap { $0 > 0 ? $0 : nil }
    }

    var isEmpty: Bool {
        healthPercent == nil && cycleCount == nil && temperatureCelsius == nil && voltage == nil
            && adapterWatts == nil
    }
}
