import Foundation

/// A turn's ID arrives twice and either can be late, so Stop can beat both.
@main
@MainActor
struct CodexTurnTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        await aCustomProviderIsReadyWithoutAnAccount()
        await aColdTurnChecksAccessItself()
        await aSignedOutRouteIsNeverReady()
        await stopBeforeTurnStartedStillInterrupts()
        await aTurnNamedTwiceIsInterruptedOnce()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// A custom provider's `account/read` is no account and `requiresOpenaiAuth: false`.
    static func aCustomProviderIsReadyWithoutAnAccount() async {
        guard let server = StubServer(mode: "api-auth") else {
            expect(false, "the custom provider stub installs")
            return
        }
        let manager = ChatGPTSubscriptionManager(supportDirectory: server.root)
        defer {
            manager.stop()
            server.tearDown()
        }

        await manager.refresh().value
        expect(
            manager.isConnected && manager.access == .provider && manager.account == nil,
            "a custom provider is ready without an OpenAI account")
        expect(
            manager.models.map(\.id) == ["custom-model"],
            "the custom provider's models are listed")

        let first = await reply(from: manager)
        let second = await reply(from: manager)
        expect(
            first.text == "ready" && second.text == "ready",
            "turns run on the custom provider: \(first.error ?? second.error ?? "")")
        expect(
            server.received.split(separator: "\n").count { $0 == "account/read" } == 1,
            "access is read once by the check, not again before every turn")
    }

    /// The turn guard, not only the status check, has to accept a custom provider.
    static func aColdTurnChecksAccessItself() async {
        guard let server = StubServer(mode: "api-auth") else {
            expect(false, "the custom provider stub installs")
            return
        }
        let manager = ChatGPTSubscriptionManager(supportDirectory: server.root)
        defer {
            manager.stop()
            server.tearDown()
        }

        let cold = await reply(from: manager)
        expect(
            cold.text == "ready" && manager.isConnected && manager.access == .provider,
            "a turn with no check before it runs on a custom provider: \(cold.error ?? "")")
    }

    /// No account means sign-in, unless Codex says outright that none is needed.
    static func aSignedOutRouteIsNeverReady() async {
        for mode in ["auth-required", "auth-undetermined"] {
            guard let server = StubServer(mode: mode) else {
                expect(false, "the \(mode) stub installs")
                continue
            }
            let checked = ChatGPTSubscriptionManager(supportDirectory: server.root)
            await checked.refresh().value
            expect(
                checked.phase == .signedOut && !checked.isConnected && checked.models.isEmpty,
                "\(mode): a check without an account is signed out")
            checked.stop()

            let stops = { server.received.split(separator: "\n").count { $0 == "stdin-closed" } }
            let checkStopped = await server.awaitCondition { stops() == 1 }
            let cold = ChatGPTSubscriptionManager(supportDirectory: server.root)
            let attempt = await reply(from: cold)
            expect(
                attempt.error?.contains("codex login") == true && cold.phase == .signedOut,
                "\(mode): a turn without an account asks for sign-in and shows signed out")
            let turnStopped = await server.awaitCondition { stops() == 2 }
            expect(
                checkStopped && turnStopped,
                "\(mode): the signed-out server is stopped, as after a check")
            cold.stop()
            server.tearDown()
        }
    }

    private static func reply(
        from manager: ChatGPTSubscriptionManager
    ) async -> (text: String, error: String?) {
        let stream = manager.turns.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "custom-model", effort: nil)
        var text = ""
        do {
            for try await event in stream {
                if case .text(let delta) = event { text += delta }
            }
        } catch {
            return (text, error.localizedDescription)
        }
        return (text, nil)
    }

    /// Stop arrives before anything names the turn, and `turn/start` never answers.
    static func stopBeforeTurnStartedStillInterrupts() async {
        guard let server = StubServer(mode: "hold-turn") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let turn = server.startTurn(effort: "high")
        guard await server.awaitMark("turn-start-received") else {
            expect(false, "the stub app-server is asked to start a turn")
            return
        }
        expect(
            server.received.contains(#""effort":"high""#),
            "reasoning effort belongs to the turn and does not mutate Codex settings")
        expect(
            !server.received.contains("config/value/write"),
            "a Onecast turn never writes the user's Codex configuration")

        turn.cancel()
        let dropped = await server.awaitCondition { !server.runner.isActive }
        expect(dropped, "Stop drops a turn that nothing has named yet")

        // Only now does the server name the turn — after the runner has already let the thread go.
        server.mark("stop-landed")
        let interrupted = await server.awaitLog("interrupt:thread-1:turn-1")
        expect(interrupted, "a Stop that beat turn/started still interrupts the turn that starts")
    }

    /// Both names arrive for the same Stopped turn. Interrupting per name would send two.
    static func aTurnNamedTwiceIsInterruptedOnce() async {
        guard let server = StubServer(mode: "hold-both") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let turn = server.startTurn()
        guard await server.awaitMark("turn-start-received") else {
            expect(false, "the stub app-server is asked to start a turn")
            return
        }

        turn.cancel()
        _ = await server.awaitCondition { !server.runner.isActive }
        server.mark("stop-landed")

        let interrupted = await server.awaitLog("interrupt:thread-1:turn-1")
        expect(interrupted, "a Stopped turn is interrupted as soon as its ID arrives")
        // Give a second interrupt every chance to show up before ruling it out.
        _ = await server.awaitCondition(timeout: .milliseconds(400)) { server.interrupts > 1 }
        expect(server.interrupts == 1, "the turn's second name spends no second interrupt")
    }
}

/// A real client against the stub server in `Tests/ai-fixtures/codex-stub.js`.
@MainActor
final class StubServer {
    let root: URL
    let client: CodexAppServerClient
    let runner: CodexTurnRunner

    init?(mode: String) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-turn-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executable = root.appending(path: "bin/codex")
        do {
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "Tests/ai-fixtures/codex-stub.js"), to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        } catch {
            print("the stub app-server could not be installed: \(error)")
            return nil
        }

        // The locator walks PATH, so the stub only sits in front of any real `codex`.
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", "\(executable.deletingLastPathComponent().path):\(inherited)", 1)
        setenv("TC_STUB_ROOT", root.path, 1)
        setenv("TC_STUB_MODE", mode, 1)

        let client = CodexAppServerClient(
            codexHome: root.appending(path: "home", directoryHint: .isDirectory),
            workspace: root.appending(path: "work", directoryHint: .isDirectory))
        let runner = CodexTurnRunner(client: client)
        runner.connect = {
            try await client.start()
            return []
        }
        client.onNotification = { method, params in
            runner.handle(method: method, params: params)
        }

        self.root = root
        self.client = client
        self.runner = runner
    }

    /// What the app does: a task iterating the provider stream, where Stop is its cancellation.
    func startTurn(effort: String? = nil) -> Task<Void, Never> {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: effort)
        return Task {
            do {
                for try await _ in stream {}
            } catch {}
        }
    }

    var received: String {
        (try? String(contentsOf: root.appending(path: "received.log"), encoding: .utf8)) ?? ""
    }

    var interrupts: Int {
        received.split(separator: "\n").count { $0.hasPrefix("interrupt:") }
    }

    func mark(_ name: String) {
        FileManager.default.createFile(atPath: root.appending(path: name).path, contents: nil)
    }

    func awaitMark(_ name: String) async -> Bool {
        await awaitCondition {
            FileManager.default.fileExists(atPath: self.root.appending(path: name).path)
        }
    }

    func awaitLog(_ line: String) async -> Bool {
        await awaitCondition { self.received.contains(line) }
    }

    /// Polls rather than sleeping, so a pass costs what it needs and a failure still ends.
    func awaitCondition(
        timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    func tearDown() {
        client.stop()
        try? FileManager.default.removeItem(at: root)
    }
}
