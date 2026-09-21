import Foundation
import Network

/// In-app half of computer use: the CLI's helper relays MCP calls here, where the TCC grants live.
@MainActor
final class ComputerUseBridge {
    private struct Request: Sendable {
        let token: String
        let action: String
        let arguments: String
    }

    /// Holds the TCC-granted work; the one controller shared with the in-process route.
    private let tool: ComputerUseTool

    init(controller: ComputerController) {
        tool = ComputerUseTool(controller: controller)
    }

    /// One loopback listener on a kernel-assigned port, kept alive across arms for its accept loop.
    private var listener: NetworkListener<TLV>?
    private var listenerTask: Task<Void, Never>?
    private var port: UInt16?
    private var bindTask: Task<UInt16?, Never>?
    /// Identifies the live attempt; a stale accept loop's failure only tears down its own generation.
    private var generation = 0

    /// The token gate; refuses an unknown, disarmed, or expired token. Bounded vs dead helpers.
    private var ledger = ComputerUseTokenLedger()

    /// Builds the MCP server the CLI spawns; awaits `.ready` so its handshake names a bound port.
    func server(armed: @escaping @MainActor () -> Bool) async -> AICLIMCPServer? {
        guard let port = await ensureListening() else { return nil }
        Self.sweepStaleHandshakes()
        let token = Self.newToken()
        ledger.issue(token, armed: armed, now: Date())
        guard let handshake = Self.writeHandshake(port: port, token: token) else { return nil }
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ComputerUseHelper").path
        return AICLIMCPServer(
            slug: Self.reservedSlug,
            transport: .stdio(command: helper, arguments: [handshake]),
            headerValue: "", environment: [:])
    }

    /// Deduplicates the bind: a second send while one is in flight awaits it, never a second listener.
    private func ensureListening() async -> UInt16? {
        if let port { return port }
        if let bindTask { return await bindTask.value }
        let task = Task { [weak self] () -> UInt16? in
            let bound = await self?.bind()
            self?.bindTask = nil
            return bound
        }
        bindTask = task
        return await task.value
    }

    /// Binds once, to a kernel-assigned loopback port, and keeps the accept loop for later arms.
    private func bind() async -> UInt16? {
        generation += 1
        let attempt = generation
        let parameters = NWParametersBuilder({ TLV { TCP { IP() } } })
            .localEndpoint(.hostPort(host: .ipv4(.loopback), port: .any))
            .localOnly(true)
        guard let listener = try? NetworkListener(using: parameters) else {
            listenerFailed(attempt)
            return nil
        }
        self.listener = listener
        guard let bound = await readyPort(of: listener, generation: attempt), attempt == generation
        else {
            listenerFailed(attempt)
            return nil
        }
        port = bound
        return bound
    }

    /// Starts the accept loop and resolves once bound, to the port the kernel handed out.
    private func readyPort(of listener: NetworkListener<TLV>, generation: Int) async -> UInt16? {
        await withCheckedContinuation { continuation in
            let gate = ContinuationGate(continuation)
            listener.onStateUpdate { listener, state in
                switch state {
                case .ready: gate.resume(returning: listener.port?.rawValue)
                case .failed, .cancelled: gate.resume(returning: nil)
                default: break
                }
            }
            listenerTask = Task { [weak self] in
                do {
                    try await listener.run { [weak self] connection in
                        await self?.serve(connection)
                    }
                } catch {
                    gate.resume(returning: nil)
                    self?.listenerFailed(generation)
                }
            }
        }
    }

    /// A stale attempt's failure is ignored, so it can't tear down a listener a later arm rebound.
    private func listenerFailed(_ generation: Int) {
        guard generation == self.generation else { return }
        self.generation += 1
        listenerTask?.cancel()
        listenerTask = nil
        listener = nil
        port = nil
    }

    /// One TLV request in, one TLV reply out; returning closes the connection.
    private func serve(_ connection: NetworkConnection<TLV>) async {
        let reply: Data
        if let request = try? await connection.receive().content, let parsed = Self.parse(request) {
            reply = await execute(parsed)
        } else {
            reply = Self.encode(["ok": false, "error": "Bad request."])
        }
        try? await connection.send(reply, type: 1, lastMessage: true)
    }

    private func execute(_ request: Request) async -> Data {
        guard ledger.authorizes(request.token, now: Date()) else {
            return Self.encode(["ok": false, "error": "Computer use is not enabled in Onecast."])
        }
        let call = AIToolCall(
            id: "bridge", name: "computer__" + request.action, arguments: request.arguments)
        let result = await tool.invoke(call)
        var object: [String: Any] = ["ok": !result.isError, "text": result.content]
        if let image = result.images.first {
            object["image"] = image.data.base64EncodedString()
            object["mime"] = image.mimeType
        }
        return Self.encode(object)
    }

    // MARK: Wire

    private static func parse(_ data: Data) -> Request? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            let token = dictionary["token"] as? String,
            let action = dictionary["action"] as? String
        else { return nil }
        let arguments = dictionary["arguments"].flatMap {
            try? JSONSerialization.data(withJSONObject: $0)
        }
        return Request(
            token: token, action: action,
            arguments: arguments.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
    }

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{\"ok\":false}".utf8)
    }

    /// Unique handshake per issuance (port, token, schemas); the helper reads once and deletes it.
    private static func writeHandshake(port: UInt16, token: String) -> String? {
        let tools = ComputerUseTool.tools.map { tool -> [String: Any] in
            [
                "name": String(tool.name.dropFirst("computer__".count)),
                "description": tool.description,
                "inputSchema": tool.parameters.jsonObject,
            ]
        }
        let object: [String: Any] = ["port": Int(port), "token": token, "tools": tools]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        let name = Self.handshakePrefix + "\(UUID().uuidString).json"
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        guard
            FileManager.default.createFile(
                atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
        else { return nil }
        return path
    }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// A `_` can't occur in a slug (`MCPSlug.normalize` uses `-`), so this built-in won't collide.
    static let reservedSlug = "onecast_computer"

    private static var handshakePrefix: String {
        (Bundle.main.bundleIdentifier ?? "com.onecast.app") + ".computeruse."
    }

    /// Deletes our handshakes a helper never consumed, so a failed CLI launch leaves no live token.
    private static func sweepStaleHandshakes() {
        let directory = NSTemporaryDirectory()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-120)
        for name in names where name.hasPrefix(handshakePrefix) {
            let path = (directory as NSString).appendingPathComponent(name)
            let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[
                .modificationDate]
            if let modified = modified as? Date, modified < cutoff {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }
}

/// Guards a checked continuation so the listener's repeated state callbacks resume it exactly once.
@MainActor
private final class ContinuationGate {
    private var continuation: CheckedContinuation<UInt16?, Never>?

    init(_ continuation: CheckedContinuation<UInt16?, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: UInt16?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
