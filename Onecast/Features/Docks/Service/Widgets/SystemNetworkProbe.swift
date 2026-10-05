import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

/// The reads behind Network Activity: byte counters, link state and the default route.
enum SystemNetworkProbe {
    struct Link: Sendable, Equatable {
        let isUp: Bool
        let address: String?
    }

    struct Reading: Sendable {
        let counters: [String: SystemNetworkTracker.Counters]
        let links: [String: Link]
        let primaryName: String?
    }

    /// What CoreWLAN offers without Location access; `ssid` is nil whenever macOS withholds it.
    struct WiFi: Sendable, Equatable {
        let interfaceName: String?
        let ssid: String?
        /// Received signal strength in dBm; nil when not associated.
        let signal: Int?
        /// Link speed in Mbit/s.
        let transmitRate: Double?
    }

    static func read() -> Reading {
        var counters: [String: SystemNetworkTracker.Counters] = [:]
        var up: [String: Bool] = [:]
        var addresses: [String: String] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else {
            return Reading(counters: [:], links: [:], primaryName: primaryInterface())
        }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: head, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr else { continue }
            let name = String(cString: entry.ifa_name)
            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                guard let data = entry.ifa_data else { continue }
                let statistics = data.assumingMemoryBound(to: if_data.self).pointee
                counters[name] = SystemNetworkTracker.Counters(
                    received: statistics.ifi_ibytes, sent: statistics.ifi_obytes)
                let required = UInt32(IFF_UP | IFF_RUNNING)
                up[name] = entry.ifa_flags & required == required
            case AF_INET:
                if addresses[name] == nil { addresses[name] = numericHost(address) }
            default:
                continue
            }
        }
        let links = up.reduce(into: [String: Link]()) {
            $0[$1.key] = Link(isUp: $1.value, address: addresses[$1.key])
        }
        return Reading(counters: counters, links: links, primaryName: primaryInterface())
    }

    /// The interface the default IPv4 route leaves by, from the system configuration store.
    static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Onecast" as CFString, nil, nil),
            let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    static func wifi() -> WiFi? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return nil }
        let signal = interface.rssiValue()
        let rate = interface.transmitRate()
        return WiFi(
            interfaceName: interface.interfaceName, ssid: interface.ssid(),
            signal: signal == 0 ? nil : signal, transmitRate: rate > 0 ? rate : nil)
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0,
            NI_NUMERICHOST)
        guard status == 0 else { return nil }
        return String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
}
