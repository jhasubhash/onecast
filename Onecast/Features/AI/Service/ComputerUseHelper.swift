import Darwin
import Foundation

/// A zero-capability MCP relay: captures nothing, forwards each tools/call to the app's bridge.
@main
enum ComputerUseHelper {
    static func main() {
        let handshakePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
        ComputerMCPServer(handshake: handshakePath.flatMap(Handshake.read)).run()
    }
}

private struct Handshake {
    let port: UInt16
    let token: String
    let tools: [Any]

    /// Read once, then delete: the token must not outlive the helper on disk.
    static func read(_ path: String) -> Handshake? {
        guard let data = FileManager.default.contents(atPath: path),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let port = object["port"] as? Int, let token = object["token"] as? String
        else { return nil }
        try? FileManager.default.removeItem(atPath: path)
        return Handshake(port: UInt16(port), token: token, tools: object["tools"] as? [Any] ?? [])
    }
}

/// Newline-delimited JSON-RPC 2.0 over stdio (MCP stdio transport); unknown methods get not-found.
private struct ComputerMCPServer {
    let handshake: Handshake?

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty,
                let data = line.data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            guard let response = handle(message) else { continue }
            emit(response)
        }
    }

    /// Returns the response object, or nil for a notification (no id) that takes no reply.
    private func handle(_ message: [String: Any]) -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String
        guard let id else { return nil }
        switch method {
        case "initialize":
            return success(
                id,
                [
                    "protocolVersion": "2025-06-18",
                    "capabilities": ["tools": [String: Any]()],
                    "serverInfo": ["name": "onecast-computer-use", "version": "1"],
                ])
        case "ping":
            return success(id, [String: Any]())
        case "tools/list":
            return success(id, ["tools": handshake?.tools ?? []])
        case "tools/call":
            return call(id, params: message["params"] as? [String: Any] ?? [:])
        default:
            return failure(id, code: -32601, message: "Method not found: \(method ?? "nil").")
        }
    }

    private func call(_ id: Any, params: [String: Any]) -> [String: Any] {
        guard let handshake else { return toolError(id, "Onecast computer use is not configured.") }
        guard let name = params["name"] as? String else {
            return toolError(id, "Missing tool name.")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let request: [String: Any] = [
            "token": handshake.token, "action": name, "arguments": arguments,
        ]
        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
            let replyData = Bridge.roundTrip(port: handshake.port, request: requestData),
            let reply = try? JSONSerialization.jsonObject(with: replyData) as? [String: Any]
        else {
            return toolError(id, "Onecast is not reachable. Is it running?")
        }
        if reply["ok"] as? Bool != true {
            let message = reply["error"] as? String ?? reply["text"] as? String
            return toolError(id, message ?? "The action failed.")
        }
        var content: [[String: Any]] = [["type": "text", "text": reply["text"] as? String ?? ""]]
        if let image = reply["image"] as? String {
            content.append([
                "type": "image", "data": image, "mimeType": reply["mime"] as? String ?? "image/png",
            ])
        }
        return success(id, ["content": content, "isError": false])
    }

    // MARK: JSON-RPC framing

    private func success(_ id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func failure(_ id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    /// A failed action is a readable tool result, never a protocol error, so the model can recover.
    private func toolError(_ id: Any, _ text: String) -> [String: Any] {
        success(id, ["content": [["type": "text", "text": text]], "isError": true])
    }

    private func emit(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}

/// The loopback client to the app's bridge: one request line, read the reply to EOF, close.
private enum Bridge {
    static func roundTrip(port: UInt16, request: Data) -> Data? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        var frame = request
        frame.append(0x0A)
        guard write(fd, frame) else { return nil }
        return readToEnd(fd)
    }

    private static func write(_ fd: Int32, _ payload: Data) -> Bool {
        payload.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let n = Darwin.write(fd, pointer, remaining)
                if n <= 0 { return false }
                pointer = pointer.advanced(by: n)
                remaining -= n
            }
            return true
        }
    }

    /// Chunked read: a screenshot reply is a base64 blob framed by EOF; strip trailing newline.
    private static func readToEnd(_ fd: Int32) -> Data? {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n <= 0 { break }
            data.append(contentsOf: chunk[0..<n])
        }
        if data.last == 0x0A { data.removeLast() }
        return data.isEmpty ? nil : data
    }
}
