import Foundation

/// One tick of network activity: every interface's rate, and which one carries the default route.
struct SystemNetworkSample: Sendable, Equatable {
    struct Interface: Sendable, Equatable, Identifiable {
        let name: String
        let kind: SystemNetworkInterfaceKind
        /// Up and running, so a link that exists but carries nothing reads as idle, not off.
        let isUp: Bool
        let address: String?
        var throughput: SystemNetworkTracker.Throughput
        var traffic: SystemNetworkTracker.Traffic

        var id: String { name }
    }

    /// Which rate a tile graphs.
    enum Scope: String, Sendable, CaseIterable {
        case primary, total
    }

    let interfaces: [Interface]
    let primary: Interface?

    static let empty = SystemNetworkSample(interfaces: [], primaryName: nil)

    /// Without a default-route name, the busiest physical link that is up stands in.
    init(interfaces: [Interface], primaryName: String?) {
        self.interfaces = interfaces
        let physical = interfaces.filter { $0.kind.countsTowardTotal && $0.isUp }
        primary =
            interfaces.first { $0.name == primaryName && $0.isUp }
            ?? physical.max { Self.activity($0).lexicographicallyPrecedes(Self.activity($1)) }
    }

    /// What the popover lists: links that are up and either addressed or have moved bytes.
    var visibleInterfaces: [Interface] {
        interfaces.filter {
            $0.kind != .loopback && $0.isUp
                && ($0.address != nil || $0.traffic.received + $0.traffic.sent > 0)
        }
    }

    /// Summed over physical links only, so a VPN tunnel never doubles what crossed the wire.
    var total: SystemNetworkTracker.Throughput {
        interfaces.filter(\.kind.countsTowardTotal).reduce(.zero) {
            SystemNetworkTracker.Throughput(
                download: $0.download + $1.throughput.download,
                upload: $0.upload + $1.throughput.upload)
        }
    }

    var totalTraffic: SystemNetworkTracker.Traffic {
        interfaces.filter(\.kind.countsTowardTotal).reduce(
            SystemNetworkTracker.Traffic(received: 0, sent: 0)
        ) {
            SystemNetworkTracker.Traffic(
                received: $0.received + $1.traffic.received, sent: $0.sent + $1.traffic.sent)
        }
    }

    func throughput(for scope: Scope) -> SystemNetworkTracker.Throughput {
        switch scope {
        case .primary: primary?.throughput ?? .zero
        case .total: total
        }
    }

    /// Current rate first, lifetime bytes as the tie-break between two idle links.
    private static func activity(_ interface: Interface) -> [Double] {
        [
            interface.throughput.download + interface.throughput.upload,
            Double(interface.traffic.received + interface.traffic.sent),
        ]
    }
}
