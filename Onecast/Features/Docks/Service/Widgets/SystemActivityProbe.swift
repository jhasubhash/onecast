import Darwin
import Foundation

// Snapshot the mutable C global `mach_task_self_`, so concurrent code never reads it raw.
private let machTaskSelf = mach_task_self_

/// The kernel reads behind System Activity. Each is a cheap syscall, safe to run off the main actor.
enum SystemActivityProbe {
    struct Reading: Sendable {
        let ticks: [SystemCPUUsage.Ticks]
        let memory: SystemMemoryUsage?
        let loadAverages: [Double]
        let bootDate: Date?
    }

    static func read() -> Reading {
        Reading(
            ticks: cpuTicks(), memory: memory(), loadAverages: loadAverages(), bootDate: bootDate())
    }

    static func cpuTicks() -> [SystemCPUUsage.Ticks] {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            _ = vm_deallocate(
                machTaskSelf, vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(processorCount)).map { core in
            let offset = core * Int(CPU_STATE_MAX)
            func ticks(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[offset + Int(state)]) }
            return SystemCPUUsage.Ticks(
                user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
        }
    }

    static func memory() -> SystemMemoryUsage? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = SystemMemoryUsage.Pages(
            free: UInt64(statistics.free_count), wired: UInt64(statistics.wire_count),
            compressed: UInt64(statistics.compressor_page_count),
            purgeable: UInt64(statistics.purgeable_count),
            internalPages: UInt64(statistics.internal_page_count),
            external: UInt64(statistics.external_page_count))
        var memory = SystemMemoryUsage(
            pages: pages, pageSize: UInt64(getpagesize()), total: ProcessInfo.processInfo.physicalMemory)
        let swap = swapUsage()
        memory.swapUsed = swap.used
        memory.swapTotal = swap.total
        memory.pressure = SystemMemoryUsage.Pressure(kernelLevel: pressureLevel())
        return memory
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical; 1 if unreadable.
    static func pressureLevel() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return 1
        }
        return Int(level)
    }

    static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    static func loadAverages() -> [Double] {
        var averages = [Double](repeating: 0, count: 3)
        let count = averages.withUnsafeMutableBufferPointer {
            getloadavg($0.baseAddress, Int32($0.count))
        }
        return count == 3 ? averages : []
    }

    /// Since boot, sleep included, as `uptime` counts it; `systemUptime` stops while asleep.
    static func bootDate() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }
}
