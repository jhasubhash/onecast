import Foundation

@main
@MainActor
struct InstalledAITests {
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
        guard let fixture = Fixture() else {
            expect(false, "the installed CLI fixture starts")
            return
        }
        defer { fixture.tearDown() }
        openCodeCatalogCarriesModelVariants()
        versionKeepsPrereleaseAndBuild()
        shellAccessGatesToShellCapableRoutes()
        await openCodeRunsWithoutToolsAndDeletesItsSession(fixture)
        await claudeRunsWithoutToolsOrHistory(fixture)
        claudeMCPConfigNamesNoServers(fixture)
        await copilotMCPRouteScopesOutShell(fixture)
        await copilotEnvironmentNeutralizesAllowAll(fixture)

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static func openCodeCatalogCarriesModelVariants() {
        let output = """
            provider/model
            {
              "name": "Model",
              "variants": {
                "low": {"reasoningEffort": "low"},
                "high": {"reasoningEffort": "high"}
              }
            }
            provider/plain
            {
              "name": "Plain",
              "variants": {}
            }
            """
        let models = InstalledAIModel.openCodeCatalog(output)
        expect(
            models.first?.efforts.map(\.id) == ["low", "high"],
            "OpenCode discovery keeps each model's supported reasoning variants")
        expect(models.last?.efforts.isEmpty == true, "models without variants show no effort picker")
    }

    private static func versionKeepsPrereleaseAndBuild() {
        let cases: [(String, String?)] = [
            ("opencode2 v0.0.0-beta-19271\n", "0.0.0-beta-19271"),
            ("2.0.14 (Claude Code)\n", "2.0.14"),
            ("codex-cli 0.46.0\n", "0.46.0"),
            ("tool 1.2.3-rc.1+build.5\n", "1.2.3-rc.1+build.5"),
            ("no version here", nil),
        ]
        for (output, expected) in cases {
            let version = InstalledAIProbe.version(in: output)
            expect(version == expected, "version(in: \(output.debugDescription)) is \(String(describing: version))")
        }
    }

    /// The default-chat shell opt-in reaches only routes that honor it; other kinds get no config.
    private static func shellAccessGatesToShellCapableRoutes() {
        let expected: [(AIModelSource, Bool)] = [
            (.claude, true), (.copilot, true), (.codex, false), (.openCode, false),
        ]
        for (source, honors) in expected {
            expect(
                source.installedKind?.honorsShellAccess == honors,
                "\(source) shell gate is \(honors)")
        }
        for source in [AIModelSource.appleIntelligence, .api(UUID())] {
            expect(
                source.installedKind == nil,
                "\(source) has no installed CLI, so the shell gate can never arm it")
        }
    }

    private static func openCodeRunsWithoutToolsAndDeletesItsSession(_ fixture: Fixture) async {
        let events = await fixture.events(
            kind: .openCode, model: "provider/model", effort: "high")
        expect(events.contains(.text("OpenCode reply")), "OpenCode text reaches the provider stream")
        expect(events.last == .finished, "OpenCode finishes the provider stream")
        let arguments = fixture.read("opencode-args.log")
        expect(
            arguments.contains("--pure") && arguments.contains("--format")
                && arguments.contains("provider/model") && arguments.contains("--variant")
                && arguments.contains("high"),
            "OpenCode runs pure with JSON output, the chosen model and its variant")
        let configuration = fixture.read("opencode-environment.log")
        expect(
            configuration.contains("\"permission\":\"deny\"")
                && configuration.contains("\"share\":\"disabled\""),
            "OpenCode receives deny-all permissions and disabled sharing")
        let deleted = await fixture.awaitFile("deleted.log", containing: "ses_stub")
        if !deleted { print("OpenCode invocations: \(fixture.read("opencode-args.log"))") }
        expect(deleted, "OpenCode deletes the session created for the reply")
        fixture.expectPrompt("opencode-prompt.log")
    }

    private static func claudeRunsWithoutToolsOrHistory(_ fixture: Fixture) async {
        let events = await fixture.events(kind: .claude, model: "sonnet", effort: "xhigh")
        expect(events.contains(.text("Claude reply")), "Claude text reaches the provider stream")
        expect(events.last == .finished, "Claude finishes the provider stream")
        let arguments = fixture.read("claude-args.log")
        for flag in [
            "--no-session-persistence", "--disable-slash-commands", "--tools",
            "--disallowedTools", "--strict-mcp-config", "--no-chrome"
        ] {
            expect(arguments.contains(flag), "Claude runs with \(flag)")
        }
        // `--bare` reads neither OAuth nor the keychain, so it refuses the sign-in this route reuses.
        expect(!arguments.contains("--bare"), "Claude never runs with --bare")
        expect(
            arguments.contains("--effort") && arguments.contains("xhigh"),
            "Claude receives the chosen reasoning effort")
        fixture.expectPrompt("claude-prompt.log")
    }

    /// The CLI rejects a bare `{}` before the turn starts, and a stub argv would never notice.
    private static func claudeMCPConfigNamesNoServers(_ fixture: Fixture) {
        let argv = fixture.arguments("claude-args.log")
        guard let index = argv.firstIndex(of: "--mcp-config"), index + 1 < argv.count,
            let data = argv[index + 1].data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            expect(false, "Claude passes a decodable --mcp-config object")
            return
        }
        expect(
            object.count == 1 && object["mcpServers"] is [String: Any],
            "Claude's --mcp-config declares an empty mcpServers record")
    }

    /// Copilot's MCP-only route allows only the namespaced injected server, never native shell.
    private static func copilotMCPRouteScopesOutShell(_ fixture: Fixture) async {
        let computer = AICLIMCPServer(
            slug: "computer",
            transport: .http(url: "http://127.0.0.1:0/mcp", headerName: "x-onecast-token"),
            headerValue: "", environment: [:])
        let scoped = await fixture.copilotArguments(
            AICLIToolConfig(servers: [computer], allowShell: false))
        expect(
            !scoped.contains("--allow-all-tools") && !scoped.contains("--allow-all"),
            "Copilot's MCP-only route never grants blanket tool access")
        expect(
            allows(scoped, computer.copilotServerName),
            "Copilot's MCP-only route allows the injected server under its namespaced name")
        expect(
            copilotConfigServerKeys(scoped) == [computer.copilotServerName],
            "Copilot's --additional-mcp-config registers the server under the same namespaced name")
        for kind in ["shell", "read", "write", "url", "memory"] {
            expect(
                denies(scoped, kind),
                "Copilot's MCP-only route denies native `\(kind)` so allow-all can't grant it")
        }

        let shellSlug = AICLIMCPServer(
            slug: "shell",
            transport: .http(url: "http://127.0.0.1:0/mcp", headerName: "x-onecast-token"),
            headerValue: "", environment: [:])
        let shadow = await fixture.copilotArguments(
            AICLIToolConfig(servers: [shellSlug], allowShell: false))
        expect(
            !allows(shadow, "shell") && allows(shadow, shellSlug.copilotServerName),
            "a `shell` MCP slug is namespaced, never granting the built-in shell permission")
        expect(
            copilotConfigServerKeys(shadow) == [shellSlug.copilotServerName],
            "a `shell` slug's config key is namespaced, matching its --allow-tool value")

        let full = await fixture.copilotArguments(
            AICLIToolConfig(servers: [computer], allowShell: true))
        expect(
            full.contains("--allow-all") && !full.contains("--allow-tool")
                && !full.contains("--deny-tool"),
            "the allowShell opt-in grants full access with --allow-all, denying nothing")
    }

    /// The `mcpServers` keys in the `--additional-mcp-config` payload; must match `--allow-tool`.
    private static func copilotConfigServerKeys(_ argv: [String]) -> [String] {
        guard let index = argv.firstIndex(of: "--additional-mcp-config"), index + 1 < argv.count,
            let data = argv[index + 1].data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let servers = object["mcpServers"] as? [String: Any]
        else { return [] }
        return servers.keys.sorted()
    }

    private static func allows(_ argv: [String], _ name: String) -> Bool {
        flagValues(argv, "--allow-tool").contains(name)
    }

    private static func denies(_ argv: [String], _ kind: String) -> Bool {
        flagValues(argv, "--deny-tool").contains(kind)
    }

    /// The value following each occurrence of `flag` in argv, e.g. every `--allow-tool <name>`.
    private static func flagValues(_ argv: [String], _ flag: String) -> [String] {
        argv.indices.compactMap { index in
            argv[index] == flag && index + 1 < argv.count ? argv[index + 1] : nil
        }
    }

    /// COPILOT_ALLOW_ALL=true escapes the deny flags and the flag-less route; force it off.
    private static func copilotEnvironmentNeutralizesAllowAll(_ fixture: Fixture) async {
        let server = AICLIMCPServer(
            slug: "computer",
            transport: .http(url: "http://127.0.0.1:0/mcp", headerName: "x-onecast-token"),
            headerValue: "", environment: [:])
        let plain = await fixture.copilotEnvironment(nil, inherited: ["COPILOT_ALLOW_ALL": "true"])
        expect(
            plain["COPILOT_ALLOW_ALL"] == "false",
            "an inherited COPILOT_ALLOW_ALL is forced off on Copilot's flag-less text route")
        let scoped = await fixture.copilotEnvironment(
            AICLIToolConfig(servers: [server], allowShell: false),
            inherited: ["COPILOT_ALLOW_ALL": "true"])
        expect(
            scoped["COPILOT_ALLOW_ALL"] == "false",
            "an inherited COPILOT_ALLOW_ALL is forced off on Copilot's MCP-only route")
        let injected = await fixture.copilotEnvironment(
            AICLIToolConfig(
                servers: [server], allowShell: false, environment: ["COPILOT_ALLOW_ALL": "true"]))
        expect(
            injected["COPILOT_ALLOW_ALL"] == "false",
            "an assistant-injected COPILOT_ALLOW_ALL is overwritten after the env merge")
        let opted = await fixture.copilotEnvironment(
            AICLIToolConfig(servers: [server], allowShell: true),
            inherited: ["COPILOT_ALLOW_ALL": "true"])
        expect(
            opted["COPILOT_ALLOW_ALL"] == "true",
            "the allowShell opt-in leaves COPILOT_ALLOW_ALL untouched")
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let workspace: URL
    let executables: [InstalledAIKind: URL]

    init?() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "installed-ai-\(UUID().uuidString)", directoryHint: .isDirectory)
        workspace = root.appending(path: "workspace", directoryHint: .isDirectory)
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            var values: [InstalledAIKind: URL] = [:]
            for kind in [InstalledAIKind.claude, .openCode, .copilot] {
                let executable = bin.appending(path: kind.command)
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: "Tests/ai-fixtures/installed-cli-stub.js"),
                    to: executable)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: executable.path)
                values[kind] = executable
            }
            executables = values
            let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
            setenv("PATH", bin.path + ":" + inheritedPath, 1)
            setenv("TC_INSTALLED_STUB_ROOT", root.path, 1)
        } catch {
            print("fixture setup failed: \(error)")
            return nil
        }
    }

    func events(kind: InstalledAIKind, model: String, effort: String?) async -> [AIStreamEvent] {
        guard let executable = executables[kind] else { return [] }
        let provider = InstalledCLIProvider(
            kind: kind, executable: executable,
            model: model, effort: effort, workspace: workspace)
        let request = AIRequest(
            instructions: "Follow the custom instruction.",
            messages: [
                AIMessage(role: .user, text: "First question"),
                AIMessage(role: .assistant, text: "First answer"),
                AIMessage(role: .user, text: "Final question")
            ])
        do {
            var events: [AIStreamEvent] = []
            for try await event in provider.stream(request) { events.append(event) }
            return events
        } catch {
            print("\(kind.title) stream failed: \(error)")
            return []
        }
    }

    func copilotArguments(_ toolConfig: AICLIToolConfig) async -> [String] {
        guard let executable = executables[.copilot] else { return [] }
        let provider = InstalledCLIProvider(
            kind: .copilot, executable: executable, model: "gpt-5-codex", effort: nil,
            workspace: workspace, toolConfig: toolConfig)
        let request = AIRequest(
            instructions: "Follow the custom instruction.",
            messages: [AIMessage(role: .user, text: "Play music")])
        do { for try await _ in provider.stream(request) {} } catch {}
        guard let line = read("copilot-args.log").split(separator: "\n").last,
            let data = line.data(using: .utf8),
            let argv = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return argv
    }

    /// Runs a Copilot stream and returns the child's environment for the given inherited vars.
    func copilotEnvironment(
        _ toolConfig: AICLIToolConfig?, inherited: [String: String] = [:]
    ) async -> [String: String] {
        guard let executable = executables[.copilot] else { return [:] }
        let restore: [(String, String?)] = inherited.keys.map {
            ($0, ProcessInfo.processInfo.environment[$0])
        }
        for (key, value) in inherited { setenv(key, value, 1) }
        defer {
            for (key, value) in restore {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
        }
        let provider = InstalledCLIProvider(
            kind: .copilot, executable: executable, model: "gpt-5-codex", effort: nil,
            workspace: workspace, toolConfig: toolConfig)
        let request = AIRequest(
            instructions: "Follow the custom instruction.",
            messages: [AIMessage(role: .user, text: "Play music")])
        do { for try await _ in provider.stream(request) {} } catch {}
        guard let line = read("copilot-env.log").split(separator: "\n").last,
            let data = line.data(using: .utf8),
            let env = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return env
    }

    func expectPrompt(_ name: String) {
        let prompt = read(name)
        InstalledAITests.expect(
            prompt.contains("Follow the custom instruction.")
                && prompt.contains("First question") && prompt.contains("First answer")
                && prompt.contains("Final question"),
            "the installed CLI receives instructions and conversation history through stdin")
    }

    func arguments(_ name: String) -> [String] {
        guard let line = read(name).split(separator: "\n").first,
            let data = line.data(using: .utf8),
            let argv = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return argv
    }

    func read(_ name: String) -> String {
        (try? String(contentsOf: root.appending(path: name), encoding: .utf8)) ?? ""
    }

    func awaitFile(_ name: String, containing value: String) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if read(name).contains(value) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return read(name).contains(value)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
