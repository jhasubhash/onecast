import Foundation

@main
@MainActor
struct ComputerUseBridgeConcurrencyTests {
    static var failures = 0
    static var passes = 0
    static var handshakes: Set<String> = []

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else { failures += 1; print("✗ \(message)") }
    }

    /// Reads the port the handshake names, and records the path so the run cleans up after itself.
    static func port(of server: AICLIMCPServer?) -> Int? {
        guard let server, case .stdio(_, let args) = server.transport, let path = args.first
        else { return nil }
        handshakes.insert(path)
        guard let data = FileManager.default.contents(atPath: path),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["port"] as? Int
    }

    static func main() async {
        await concurrentArmsShareOneListener()
        await cancelledArmOverlappingRetriesShareOneListener()
        for path in handshakes { try? FileManager.default.removeItem(atPath: path) }
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func concurrentArmsShareOneListener() async {
        let bridge = ComputerUseBridge(controller: ComputerController())
        var tasks: [Task<AICLIMCPServer?, Never>] = []
        for _ in 0..<12 { tasks.append(Task { @MainActor in await bridge.server(armed: { true }) }) }
        var ports: [Int?] = []
        for task in tasks { ports.append(port(of: await task.value)) }
        expect(ports.allSatisfy { $0 != nil }, "every concurrent arm returns a bound server")
        let unique = Set(ports.compactMap { $0 })
        expect(unique.count == 1, "concurrent arms share one listener port, got \(unique.sorted())")
    }

    /// Cancelled and concurrent arms must not wedge or split the listener.
    static func cancelledArmOverlappingRetriesShareOneListener() async {
        let bridge = ComputerUseBridge(controller: ComputerController())
        let cancelled = Task { @MainActor in await bridge.server(armed: { true }) }
        cancelled.cancel()
        var tasks: [Task<AICLIMCPServer?, Never>] = []
        for _ in 0..<8 { tasks.append(Task { @MainActor in await bridge.server(armed: { true }) }) }
        _ = port(of: await cancelled.value)
        var ports: [Int?] = []
        for task in tasks { ports.append(port(of: await task.value)) }
        expect(ports.allSatisfy { $0 != nil }, "arms overlapping a cancelled one still bind")
        let unique = Set(ports.compactMap { $0 })
        expect(unique.count == 1, "arms overlapping a cancel share one port, got \(unique.sorted())")
    }
}
