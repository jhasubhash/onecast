import Foundation

/// How an extension's child process finishes, times out, and stops with the context that started it.
@main
struct ExtensionProcessTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func main() async {
        timingOut()
        readingBothPipes()
        await cancellingWait()
        reapingWithContext()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func timingOut() {
        print("\n# timing out")
        guard let background = run("sleep 30 & echo $!", timeout: 1000) else {
            return check("a backgrounded grandchild holding the pipes does not hang a timeout", false)
        }
        check("a timeout returns near its deadline", background.elapsed < 5)
        check("a timed-out run has no status", background.status is NSNull)
        check("a timed-out run names its signal", background.signal as? String == "SIGTERM")
        let grandchild = Int32((String(bytes: background.stdout, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        check("the grandchild's pid was reported", grandchild > 0)
        check("the grandchild goes with its group", eventually { kill(grandchild, 0) != 0 })

        let partial = run("echo err 1>&2; sleep 30", timeout: 1000)
        check("stderr written before a timeout survives it", partial?.stderrText == "err\n")
        check("so does its signal", partial?.signal as? String == "SIGTERM")

        let exited = run("exit 3", timeout: nil)
        check("an ordinary exit keeps its status", exited?.status as? Int == 3)
        check("and reports no signal", exited?.signal is NSNull)
    }

    static func readingBothPipes() {
        print("\n# reading both pipes")
        let command = "head -c 100000 /dev/zero 1>&2; echo done"
        for timeout in [nil, 5000.0] {
            let label = timeout == nil ? "without a timeout" : "under a timeout"
            guard let result = run(command, timeout: timeout) else {
                check("a child filling stderr before stdout closes finishes \(label)", false)
                continue
            }
            check("all of stderr arrives \(label)", result.stderr.count == 100_000)
            check("stdout still arrives \(label)", result.stdoutText == "done\n")
            check("it exits cleanly \(label)", result.status as? Int == 0)
        }
    }

    static func cancellingWait() async {
        print("\n# cancelling a wait")
        let marker = markerURL()
        let shims = ExtensionNodeShims()
        let pid = start(shims, "sleep 2; touch '\(marker.path)'")
        let waiting = Task { _ = try await ExtensionAsyncProcess.wait(.number(Double(pid))) }
        try? await Task.sleep(for: .milliseconds(300))
        let cancelledAt = Date()
        waiting.cancel()
        _ = try? await waiting.value
        check("a cancelled wait returns promptly", Date().timeIntervalSince(cancelledAt) < 1.5)
        try? await Task.sleep(for: .seconds(3))
        check("and its child never finishes", !FileManager.default.fileExists(atPath: marker.path))
    }

    static func reapingWithContext() {
        print("\n# reaping with the context")
        let unclaimed = markerURL()
        let detached = markerURL()
        let otherContext = markerURL()
        let shims = ExtensionNodeShims()
        let neighbour = ExtensionNodeShims()
        _ = start(shims, "sleep 2; touch '\(unclaimed.path)'")
        _ = start(shims, "sleep 2; touch '\(detached.path)'", detached: true)
        _ = start(neighbour, "sleep 2; touch '\(otherContext.path)'")
        shims.closeFiles()
        Thread.sleep(forTimeInterval: 3.5)
        let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path) }
        check("closing a context stops a child nobody waited on", !exists(unclaimed))
        check("a detached child outlives its context", exists(detached))
        check("another context's child is untouched", exists(otherContext))
        for url in [unclaimed, detached, otherContext] { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Helpers

    struct Result {
        let stdout: Data
        let stderr: Data
        let status: Any
        let signal: Any
        let elapsed: TimeInterval
        var stdoutText: String { String(bytes: stdout, encoding: .utf8) ?? "" }
        var stderrText: String { String(bytes: stderr, encoding: .utf8) ?? "" }
    }

    /// Off this thread with a deadline, so a regression fails the check instead of hanging the suite.
    static func run(_ command: String, timeout: Double?) -> Result? {
        var spec: [String: Any] = ["command": command, "shell": true]
        if let timeout { spec["timeout"] = timeout }
        let arguments = json([spec])
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var reply = ""
        let started = Date()
        Thread.detachNewThread {
            reply = ExtensionNodeShims().perform(api: "proc", method: "run", argsJSON: arguments)
            done.signal()
        }
        guard done.wait(timeout: .now() + 10) == .success,
            let value = envelope(reply)?["value"] as? [String: Any]
        else { return nil }
        return Result(
            stdout: Data(base64Encoded: value["stdout"] as? String ?? "") ?? Data(),
            stderr: Data(base64Encoded: value["stderr"] as? String ?? "") ?? Data(),
            status: value["status"] ?? NSNull(), signal: value["signal"] ?? NSNull(),
            elapsed: Date().timeIntervalSince(started))
    }

    static func start(_ shims: ExtensionNodeShims, _ command: String, detached: Bool = false) -> Int32 {
        let spec: [String: Any] = ["command": command, "shell": true, "detached": detached]
        let reply = shims.perform(api: "proc", method: "start", argsJSON: json([spec]))
        return (envelope(reply)?["value"] as? NSNumber)?.int32Value ?? 0
    }

    static func eventually(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    static func markerURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ext-process-\(UUID().uuidString)")
    }

    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "[]"
    }

    static func envelope(_ reply: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(reply.utf8))) as? [String: Any]
    }

    static func check(_ label: String, _ condition: Bool) {
        if condition {
            passes += 1
            print("  ok   \(label)")
        } else {
            failures += 1
            print("  FAIL \(label)")
        }
    }
}
