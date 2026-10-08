#if DEBUG
import Foundation
import Network
import os

/// Debug-only loopback HTTP endpoint an agent drives the app through. custom_docs/AGENT_CONTROL.md
@MainActor
final class AgentControlServer {
    /// Read by `Scripts/agent/`: the port, the per-launch token and the pid that owns them.
    static var handshakeURL: URL {
        AppPaths.applicationSupport().appendingPathComponent("agent-control.json")
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.onecast.app", category: "AgentControl")

    private let handle: @MainActor (AgentRequest) async -> Data
    private let token = AgentControlServer.newToken()
    private var listener: NetworkListener<TCP>?
    private var listenerTask: Task<Void, Never>?

    init(handle: @escaping @MainActor (AgentRequest) async -> Data) {
        self.handle = handle
    }

    func start() {
        guard listenerTask == nil else { return }
        let parameters = NWParametersBuilder({ TCP { IP() } })
            .localEndpoint(.hostPort(host: .ipv4(.loopback), port: .any))
            .localOnly(true)
        guard let listener = try? NetworkListener(using: parameters) else {
            Self.logger.error("Agent control could not create its listener.")
            return
        }
        self.listener = listener
        listener.onStateUpdate { [weak self] listener, state in
            guard case .ready = state, let port = listener.port?.rawValue else { return }
            Task { @MainActor in self?.writeHandshake(port: port) }
        }
        listenerTask = Task { [weak self] in
            do {
                try await listener.run { [weak self] connection in
                    await self?.serve(connection)
                }
            } catch {
                Self.logger.error("Agent control listener stopped: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        listenerTask?.cancel()
        listenerTask = nil
        listener = nil
        try? FileManager.default.removeItem(at: Self.handshakeURL)
    }

    private func serve(_ connection: NetworkConnection<TCP>) async {
        var buffer = Data()
        var parsed = AgentHTTPRequest.Parse.incomplete
        while case .incomplete = parsed {
            guard let chunk = try? await connection.receive(atMost: 64 * 1024).content,
                !chunk.isEmpty
            else { break }
            buffer.append(chunk)
            parsed = AgentHTTPRequest.parse(buffer)
        }
        let reply = await respond(to: parsed)
        try? await connection.send(reply, endOfStream: true)
    }

    private func respond(to parsed: AgentHTTPRequest.Parse) async -> Data {
        switch parsed {
        case .incomplete:
            return Self.failure(400, "Incomplete request.")
        case .malformed(let reason):
            return Self.failure(400, reason)
        case .request(let request):
            guard request.bearerToken == token else { return Self.failure(401, "Bad token.") }
            guard request.method == "POST", request.path == "/" else {
                return Self.failure(404, "POST a JSON command to /.")
            }
            do {
                let decoded = try AgentRequest.decode(request.body)
                return AgentHTTPRequest.response(status: 200, body: await handle(decoded))
            } catch {
                return Self.failure(400, error.localizedDescription)
            }
        }
    }

    private static func failure(_ status: Int, _ message: String) -> Data {
        AgentHTTPRequest.response(status: status, body: AgentReply.failure(message))
    }

    private func writeHandshake(port: UInt16) {
        let object: [String: Any] = [
            "port": Int(port), "token": token, "pid": Int(ProcessInfo.processInfo.processIdentifier),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let url = Self.handshakeURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        guard
            FileManager.default.createFile(
                atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        else {
            Self.logger.error("Agent control could not write its handshake.")
            return
        }
        Self.logger.info("Agent control listening on 127.0.0.1:\(port)")
    }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
