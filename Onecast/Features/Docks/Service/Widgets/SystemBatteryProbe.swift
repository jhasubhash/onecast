import Foundation
import IOKit
import IOKit.ps

/// The reads behind the Battery widget: the power-source list, and the pack's registry entry.
enum SystemBatteryProbe {
    /// The internal battery's state; nil on a Mac that has none.
    static func reading() -> SystemBatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                description[kIOPSIsPresentKey] as? Bool ?? true,
                let current = integer(description[kIOPSCurrentCapacityKey]),
                let maximum = integer(description[kIOPSMaxCapacityKey])
            else { continue }
            let raw = SystemBatteryReading.Raw(
                currentCapacity: current, maximumCapacity: maximum,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                onAdapter: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesToEmpty: integer(description[kIOPSTimeToEmptyKey]),
                minutesToFull: integer(description[kIOPSTimeToFullChargeKey]))
            return SystemBatteryReading(raw)
        }
        return nil
    }

    /// Health, cycles and the like from the `AppleSmartBattery` entry, read-only.
    static func details() -> SystemBatteryDetails {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return SystemBatteryDetails(.init()) }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let registry = properties?.takeRetainedValue() as? [String: Any]
        else { return SystemBatteryDetails(.init()) }
        // Newer macOS nests the capacity figures under BatteryData; older ones keep them on top.
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        let adapter = registry["AdapterDetails"] as? [String: Any] ?? [:]
        return SystemBatteryDetails(
            SystemBatteryDetails.Raw(
                designCapacity: integer(registry["DesignCapacity"]) ?? integer(data["DesignCapacity"]),
                nominalChargeCapacity: integer(data["NominalChargeCapacity"])
                    ?? integer(registry["NominalChargeCapacity"]),
                appleRawMaxCapacity: integer(registry["AppleRawMaxCapacity"]),
                legacyMaxCapacity: integer(registry["MaxCapacity"]),
                cycleCount: integer(registry["CycleCount"]),
                temperature: integer(registry["Temperature"]),
                voltageMillivolts: integer(registry["Voltage"]),
                adapterWatts: integer(adapter["Watts"])))
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}
