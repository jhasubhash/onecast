import Foundation

/// What a network interface is for, read from its BSD name.
enum SystemNetworkInterfaceKind: Sendable, Equatable {
    case ethernetOrWiFi, cellular, tunnel, bridge, peerToPeer, loopback, other

    static func classify(_ name: String) -> Self {
        if name.hasPrefix("lo") { return .loopback }
        if hasPrefix(name, "en") { return .ethernetOrWiFi }
        if name.hasPrefix("pdp_ip") { return .cellular }
        if ["utun", "ipsec", "ppp", "gif", "stf"].contains(where: { name.hasPrefix($0) }) {
            return .tunnel
        }
        if name.hasPrefix("bridge") { return .bridge }
        if ["awdl", "llw", "ap"].contains(where: { hasPrefix(name, $0) }) { return .peerToPeer }
        return .other
    }

    /// Only the links bytes physically cross; a tunnel or bridge would count the same bytes twice.
    var countsTowardTotal: Bool { self == .ethernetOrWiFi || self == .cellular }

    var title: String {
        switch self {
        case .ethernetOrWiFi: "Wi-Fi or Ethernet"
        case .cellular: "Cellular"
        case .tunnel: "Tunnel"
        case .bridge: "Bridge"
        case .peerToPeer: "Peer to peer"
        case .loopback: "Loopback"
        case .other: "Other"
        }
    }

    /// `prefix` followed by digits only, so `en0` matches and `enc0` does not.
    private static func hasPrefix(_ name: String, _ prefix: String) -> Bool {
        guard name.hasPrefix(prefix) else { return false }
        let rest = name.dropFirst(prefix.count)
        return !rest.isEmpty && rest.allSatisfy(\.isNumber)
    }
}
