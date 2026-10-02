import Foundation
import Synchronization

/// Bodies cross the bridge base64-encoded, so binary responses survive.
final class ExtensionFetcher: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    enum FetchError: LocalizedError {
        case badURL(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let url): return "Invalid URL: \(url)"
            }
        }
    }

    func request(_ spec: RenderValue?) async throws -> [String: Any] {
        let fields = spec?.objectValue ?? [:]
        let urlString = fields["url"]?.stringValue ?? ""
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw FetchError.badURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = fields["method"]?.stringValue ?? "GET"
        for (name, value) in fields["headers"]?.objectValue ?? [:] {
            guard let text = value.stringValue else { continue }
            request.setValue(text, forHTTPHeaderField: name)
        }
        if let base64 = fields["bodyBase64"]?.stringValue, let body = Data(base64Encoded: base64) {
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            guard let name = key as? String, let text = value as? String else { continue }
            headers[name.lowercased()] = text
        }
        let status = http?.statusCode ?? 200
        return [
            "status": status,
            "statusText": HTTPURLResponse.localizedString(forStatusCode: status),
            "headers": headers,
            "url": response.url?.absoluteString ?? urlString,
            "bodyBase64": data.base64EncodedString()
        ]
    }
}

/// `ExtensionNodeShims` launches a child on the JS queue; `wait` collects it off that queue.
enum ExtensionAsyncProcess {
    enum ProcessError: LocalizedError {
        case notStarted

        var errorDescription: String? { "No running child process with that pid." }
    }

    struct Child: Sendable {
        let task: Process
        let exit: ProcessExit
        let stdout: Pipe
        let stderr: Pipe

        /// How long a stopped group gets to leave politely before the signal it cannot trap.
        private static let killGrace = 2.0

        private static let signalNames: [Int32: String] = [
            SIGTERM: "SIGTERM", SIGKILL: "SIGKILL", SIGINT: "SIGINT", SIGHUP: "SIGHUP",
            SIGQUIT: "SIGQUIT"
        ]

        /// A timeout reports Node's shape, a null status beside the signal, whatever the exit was.
        func collect(timeout: Double?) -> [String: Any] {
            let deadline = timeout.flatMap {
                $0 > 0 ? DispatchTime.now() + .milliseconds(Int($0)) : nil
            }
            var output = OutputDrain(stdout: stdout, stderr: stderr)
            let timedOut = !output.read(until: deadline)
            if timedOut {
                stop()
                _ = output.read(until: .now() + .milliseconds(Int(Self.killGrace * 1000) + 500))
            }
            exit.wait()

            let killedBy =
                task.terminationReason == .uncaughtSignal
                ? Self.signalNames[task.terminationStatus] ?? "SIGTERM" : nil
            return [
                "stdout": output.stdout.base64EncodedString(),
                "stderr": output.stderr.base64EncodedString(),
                "status": timedOut ? NSNull() : Int(task.terminationStatus),
                "signal": killedBy ?? (timedOut ? "SIGTERM" : NSNull())
            ]
        }

        /// `Process` makes the child a group leader, so this takes a backgrounded grandchild too.
        func stop() {
            let group = -task.processIdentifier
            guard group < 0 else { return }
            kill(group, SIGTERM)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.killGrace) {
                kill(group, SIGKILL)
            }
        }
    }

    /// Reads both pipes in one poll, since a child blocked on a full stderr never closes stdout.
    private struct OutputDrain {
        private(set) var stdout = Data()
        private(set) var stderr = Data()
        private let stdoutDescriptor: Int32
        private var open: Set<Int32>

        init(stdout: Pipe, stderr: Pipe) {
            stdoutDescriptor = stdout.fileHandleForReading.fileDescriptor
            open = [stdoutDescriptor, stderr.fileHandleForReading.fileDescriptor]
        }

        /// True once both pipes reach EOF; false when the deadline passes first.
        mutating func read(until deadline: DispatchTime?) -> Bool {
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while !open.isEmpty {
                var descriptors = open.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
                let ready = poll(
                    &descriptors, nfds_t(descriptors.count), Self.millisecondsLeft(deadline))
                if ready == 0 { return false }
                if ready < 0 {
                    guard errno == EINTR else { return false }
                    continue
                }
                for descriptor in descriptors where descriptor.revents != 0 {
                    let count = Darwin.read(descriptor.fd, &buffer, buffer.count)
                    if count > 0 {
                        if descriptor.fd == stdoutDescriptor {
                            stdout.append(contentsOf: buffer[..<count])
                        } else {
                            stderr.append(contentsOf: buffer[..<count])
                        }
                    } else if count == 0 || errno != EINTR {
                        open.remove(descriptor.fd)
                    }
                }
            }
            return true
        }

        /// `poll`'s own forms: -1 waits forever, 0 checks once, and a long timeout clamps to Int32.
        private static func millisecondsLeft(_ deadline: DispatchTime?) -> Int32 {
            guard let deadline else { return -1 }
            let now = DispatchTime.now().uptimeNanoseconds
            guard deadline.uptimeNanoseconds > now else { return 0 }
            let milliseconds = (deadline.uptimeNanoseconds - now + 999_999) / 1_000_000
            return Int32(min(milliseconds, UInt64(Int32.max)))
        }
    }

    /// Started by `enqueue` and not yet claimed by `wait`, keyed by pid.
    private static let uncollected = Mutex<[Int32: (child: Child, timeout: Double?)]>([:])

    /// An app bundle inherits no login shell, so a bare `brew` would otherwise fail.
    static func resolveExecutable(_ command: String) -> URL? {
        let fileManager = FileManager.default
        if command.contains("/") {
            let expanded = (command as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: expanded)
                ? URL(fileURLWithPath: expanded) : nil
        }
        let search =
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [
                "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin",
                "/sbin"
            ]
        for directory in search {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// Never pruned on exit: a fast child can finish before its `wait` arrives to claim it.
    static func enqueue(_ child: Child, timeout: Double?) {
        uncollected.withLock { $0[child.task.processIdentifier] = (child, timeout) }
    }

    /// Matched by `Process` as well as pid: a reused pid may now be another extension's child.
    static func forget(_ started: [Int32: Process]) {
        for (pid, task) in started {
            let entry = uncollected.withLock { entries -> (child: Child, timeout: Double?)? in
                guard entries[pid]?.child.task === task else { return nil }
                return entries.removeValue(forKey: pid)
            }
            entry?.child.stop()
        }
    }

    /// A runtime shutting down cancels this, which stops the child rather than leaving it running.
    static func wait(_ pid: RenderValue?) async throws -> [String: Any] {
        guard let pid = pid?.doubleValue.flatMap({ Int32(exactly: $0) }),
            let entry = uncollected.withLock({ $0.removeValue(forKey: pid) })
        else { throw ProcessError.notStarted }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // The drain blocks until the child closes its output, which can be minutes away.
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: entry.child.collect(timeout: entry.timeout))
                }
            }
        } onCancel: {
            entry.child.stop()
        }
    }
}
