import Foundation

enum BrowserRelayError: LocalizedError {
    /// The endpoint is carried, not read back from the type: a relay on a non-default port is named.
    case unreachable(String)
    case unreadableList
    case noSuchTab(String)
    case timedOut(String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let endpoint):
            return
                "The browser relay is not reachable at \(endpoint). Start it with "
                + "`omp browser-relay` and turn on the omp extension in Chrome, then try again."
        case .unreadableList:
            return "The browser relay answered with a tab list Onecast could not read."
        case .noSuchTab(let id):
            return "No tab \(id) is open in the relayed Chrome; list the tabs and use one of their ids."
        case .timedOut(let method):
            return
                "The browser did not answer \(method) in time. The relay allows about 20 seconds per "
                + "call: start long work in one call and poll for it in the next."
        case .protocolError(let message):
            return "The browser refused the call: \(message)"
        }
    }
}

/// CDP through omp's browser relay, which drives the user's own Chrome and so its logged-in sessions.
final class BrowserRelayClient: Sendable {
    /// What `omp browser-relay` listens on with no `-p`, and the fallback for anything unusable.
    static let defaultPort = 9224
    /// A port a listener can hold; 0 and 65536+ are not one, so neither is ever dialled.
    static func isValidPort(_ port: Int) -> Bool { (1...65535).contains(port) }
    /// The port to dial: what the user set, or the default when they set nothing a listener holds.
    static func port(_ configured: Int?) -> Int {
        guard let configured, isValidPort(configured) else { return defaultPort }
        return configured
    }

    let endpoint: String
    /// Under the relay's own 20 s per-call limit, so its timeout never surfaces as a hung socket.
    static let callTimeout: Duration = .seconds(18)

    init(port: Int? = nil) {
        endpoint = "127.0.0.1:\(Self.port(port))"
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    func pages() async throws -> [BrowserRelayPage] {
        let data: Data
        do {
            (data, _) = try await Self.session.data(from: URL(string: "http://\(endpoint)/json/list")!)
        } catch {
            throw BrowserRelayError.unreachable(endpoint)
        }
        do {
            return try BrowserRelayPage.pages(fromList: data)
        } catch {
            throw BrowserRelayError.unreadableList
        }
    }

    /// One connection per call: attach to the tab, run the body against its session, detach.
    func withPage<T: Sendable>(
        _ id: String, _ body: (CDPConnection, String) async throws -> T
    ) async throws -> T {
        try await withConnection { cdp in
            let attached: [String: Any]
            do {
                attached = try await cdp.send(
                    "Target.attachToTarget", ["targetId": id, "flatten": true])
            } catch BrowserRelayError.protocolError {
                throw BrowserRelayError.noSuchTab(id)
            }
            guard let session = attached["sessionId"] as? String else {
                throw BrowserRelayError.noSuchTab(id)
            }
            let result = try await body(cdp, session)
            _ = try? await cdp.send("Target.detachFromTarget", ["sessionId": session])
            return result
        }
    }

    func withConnection<T: Sendable>(_ body: (CDPConnection) async throws -> T) async throws -> T {
        let socket = Self.session.webSocketTask(with: URL(string: "ws://\(endpoint)/cdp")!)
        socket.maximumMessageSize = 64 << 20
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        return try await body(CDPConnection(socket: socket, endpoint: endpoint))
    }
}

/// One caller's CDP channel: a command at a time, events skipped until its reply arrives.
final class CDPConnection {
    private let socket: URLSessionWebSocketTask
    private var nextID = 0
    /// The address this channel is dialled at, so a dropped socket names where it was dropped.
    let endpoint: String

    init(socket: URLSessionWebSocketTask, endpoint: String) {
        self.socket = socket
        self.endpoint = endpoint
    }

    func send(
        _ method: String, _ params: [String: Any] = [:], session: String? = nil,
        timeout: Duration = BrowserRelayClient.callTimeout
    ) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        var message: [String: Any] = ["id": id, "method": method, "params": params]
        if let session { message["sessionId"] = session }
        guard let text = String(bytes: try JSONSerialization.data(withJSONObject: message), encoding: .utf8)
        else { throw BrowserRelayError.protocolError("\(method) could not be encoded") }
        do {
            try await socket.send(.string(text))
        } catch {
            throw BrowserRelayError.unreachable(endpoint)
        }
        let socket = self.socket
        let started = ContinuousClock.now
        let data: Data
        do {
            // The timer closes the socket, which is what unblocks the pending receive so the group ends.
            data = try await withThrowingTaskGroup(of: Data.self) { group in
                let endpoint = self.endpoint
                group.addTask { try await Self.reply(to: id, on: socket, endpoint: endpoint) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    socket.cancel(with: .goingAway, reason: nil)
                    throw BrowserRelayError.timedOut(method)
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch BrowserRelayError.unreachable where ContinuousClock.now - started >= timeout {
            throw BrowserRelayError.timedOut(method)
        }
        let reply = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let error = reply["error"] as? [String: Any] {
            throw BrowserRelayError.protocolError(error["message"] as? String ?? "\(method) failed")
        }
        return reply["result"] as? [String: Any] ?? [:]
    }

    private static func reply(
        to id: Int, on socket: URLSessionWebSocketTask, endpoint: String
    ) async throws -> Data {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                try Task.checkCancellation()
                throw BrowserRelayError.unreachable(endpoint)
            }
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: continue
            }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["id"] as? Int == id { return data }
        }
    }
}
