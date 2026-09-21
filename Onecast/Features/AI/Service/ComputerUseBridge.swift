import Darwin
import Foundation

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

    /// Serves requests off the main thread; hops to @MainActor only to run the tool.
    private let queue = DispatchQueue(
        label: "com.onecast.computer-use-bridge", qos: .userInitiated, attributes: .concurrent)

    private var listenFD: Int32?
    private var port: UInt16?

    /// The token gate; refuses an unknown, disarmed, or expired token. Bounded vs dead helpers.
    private var ledger = ComputerUseTokenLedger()

    /// Builds the MCP server the CLI spawns; `armed` is captured, read at each call, not now.
    func server(armed: @escaping @MainActor () -> Bool) -> AICLIMCPServer? {
        guard let port = ensureListening() else { return nil }
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

    private func ensureListening() -> UInt16? {
        if let port { return port }
        guard let bound = Self.openLoopbackListener() else { return nil }
        listenFD = bound.fd
        port = bound.port
        queue.async { [weak self] in self?.acceptLoop(bound.fd) }
        return bound.port
    }

    nonisolated private func acceptLoop(_ listenFD: Int32) {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            queue.async { [weak self] in self?.serve(client) }
        }
    }

    nonisolated private func serve(_ fd: Int32) {
        guard let line = Self.readFrame(fd), let request = Self.parse(line) else {
            Self.sendFrame(fd, Self.encode(["ok": false, "error": "Bad request."]))
            Self.closeSocket(fd)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { Self.closeSocket(fd); return }
            let reply = await self.execute(request)
            self.queue.async { Self.sendFrame(fd, reply); Self.closeSocket(fd) }
        }
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

    // MARK: Socket

    private static func openLoopbackListener() -> (fd: Int32, port: UInt16)? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        // Loopback only: nothing off this machine can reach the bridge.
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return nil }
        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { close(fd); return nil }
        return (fd, UInt16(bigEndian: assigned.sin_port))
    }

    /// Reads one newline-framed request; the helper holds its write side open, so newline ends it.
    nonisolated private static func readFrame(_ fd: Int32, limit: Int = 1 << 16) -> String? {
        var data = Data()
        var byte: UInt8 = 0
        while data.count < limit {
            let n = read(fd, &byte, 1)
            if n <= 0 { return data.isEmpty ? nil : String(data: data, encoding: .utf8) }
            if byte == 0x0A { break }
            data.append(byte)
        }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func sendFrame(_ fd: Int32, _ payload: Data) {
        var frame = payload
        frame.append(0x0A)
        frame.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let n = write(fd, pointer, remaining)
                if n <= 0 { return }
                pointer = pointer.advanced(by: n)
                remaining -= n
            }
        }
    }

    nonisolated private static func closeSocket(_ fd: Int32) { close(fd) }

    nonisolated private static func parse(_ line: String) -> Request? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
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

    nonisolated private static func encode(_ object: [String: Any]) -> Data {
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
            let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate]
            if let modified = modified as? Date, modified < cutoff {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }
}
