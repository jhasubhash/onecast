import Foundation
import Observation

@MainActor
@Observable
final class InstalledAIManager {
    private(set) var statuses = Dictionary(
        uniqueKeysWithValues: InstalledAIKind.allCases.map { ($0, InstalledAIStatus()) })

    @ObservationIgnored private let workspace: URL
    @ObservationIgnored private var refreshTasks: [InstalledAIKind: Task<Void, Never>] = [:]
    /// The reader's command path and variables, asked at each launch so an edit takes the next one.
    @ObservationIgnored var launchSettings: (InstalledAIKind) -> InstalledAILaunch = { _ in
        InstalledAILaunch()
    }

    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        workspace = supportDirectory.appending(
            path: "InstalledAI/Workspace", directoryHint: .isDirectory)
    }

    func status(for kind: InstalledAIKind) -> InstalledAIStatus {
        statuses[kind] ?? InstalledAIStatus()
    }

    func models(for source: AIModelSource) -> [InstalledAIModel] {
        source.installedKind.map { status(for: $0).models } ?? []
    }

    @discardableResult
    func refresh(enabledKinds: Set<InstalledAIKind> = [.claude, .openCode, .copilot]) -> Task<Void, Never> {
        var tasks: [Task<Void, Never>] = []
        for kind in [InstalledAIKind.claude, .openCode, .copilot] {
            if enabledKinds.contains(kind) {
                tasks.append(refresh(kind: kind))
            } else {
                stop(kind: kind)
            }
        }
        return Task { for task in tasks { await task.value } }
    }

    @discardableResult
    func refresh(kind: InstalledAIKind) -> Task<Void, Never> {
        guard kind != .codex else { return Task {} }
        refreshTasks[kind]?.cancel()
        statuses[kind] = InstalledAIStatus(phase: .checking)
        let workspace = workspace
        let launch = launchSettings(kind)
        let task = Task { [weak self] in
            guard let self else { return }
            let result = await Self.probe(kind, launch: launch, workspace: workspace)
            guard !Task.isCancelled else { return }
            self.statuses[result.0] = result.1
        }
        refreshTasks[kind] = task
        return task
    }

    func ensure(enabledKinds: Set<InstalledAIKind>) -> Task<Void, Never> {
        var tasks: [Task<Void, Never>] = []
        for kind in [InstalledAIKind.claude, .openCode, .copilot] {
            guard enabledKinds.contains(kind) else {
                stop(kind: kind)
                continue
            }
            switch status(for: kind).phase {
            case .idle:
                tasks.append(refresh(kind: kind))
            case .checking:
                if let task = refreshTasks[kind] { tasks.append(task) }
            case .ready, .signInRequired, .notInstalled, .failed:
                break
            }
        }
        return Task { for task in tasks { await task.value } }
    }

    func stop() {
        for task in refreshTasks.values { task.cancel() }
        refreshTasks.removeAll()
        statuses = Dictionary(
            uniqueKeysWithValues: InstalledAIKind.allCases.map { ($0, InstalledAIStatus()) })
    }

    private func stop(kind: InstalledAIKind) {
        refreshTasks[kind]?.cancel()
        refreshTasks[kind] = nil
        statuses[kind] = InstalledAIStatus()
    }

    func provider(
        kind: InstalledAIKind, model: String, effort: String?, cliTools: AICLIToolConfig? = nil
    ) throws -> any AIProvider {
        guard kind != .codex else {
            throw AIProviderError.unavailable("Codex is handled by its app-server connection.")
        }
        let status = status(for: kind)
        guard status.phase != .notInstalled else {
            throw AIProviderError.unavailable("Install " + kind.title + " before using this model.")
        }
        guard status.phase != .signInRequired else {
            throw AIProviderError.unavailable("Sign in with `" + kind.signInCommand + "` first.")
        }
        let effort = InstalledAIModel.turnEffort(
            effort, model: model, of: kind, listed: status.models)
        return InstalledCLIProvider(
            kind: kind, executable: status.executable, model: model, effort: effort,
            workspace: workspace, launch: launchSettings(kind), toolConfig: cliTools)
    }

    private enum Command {
        case found(URL)
        case unavailable(InstalledAIStatus.Phase)
    }

    nonisolated private static func command(
        for kind: InstalledAIKind, launch: InstalledAILaunch
    ) async -> Command {
        switch launch.command() {
        case .executable(let url): return .found(url)
        case .missing(let path):
            return .unavailable(.failed(InstalledAILaunch.missingCommandMessage(path)))
        case .automatic:
            let found = await ExecutableLocator.locate(
                kind.command, extraHomePaths: kind.extraExecutablePaths)
            return found.map(Command.found) ?? .unavailable(.notInstalled)
        }
    }

    nonisolated private static func probe(
        _ kind: InstalledAIKind, launch: InstalledAILaunch, workspace: URL
    ) async -> (InstalledAIKind, InstalledAIStatus) {
        let executable: URL
        switch await command(for: kind, launch: launch) {
        case .found(let url): executable = url
        case .unavailable(let phase): return (kind, InstalledAIStatus(phase: phase))
        }
        let environment = launch.inherited(for: kind)
        let versionResult = await InstalledAIProbe.run(
            executable: executable, arguments: ["--version"], workspace: workspace,
            environment: environment)
        guard versionResult.status == 0 else {
            return (
                kind,
                InstalledAIStatus(
                    phase: .failed("The installed command could not run."),
                    executable: executable)
            )
        }
        let version = InstalledAIProbe.version(in: versionResult.output)
        switch kind {
        case .claude:
            let auth = await InstalledAIProbe.run(
                executable: executable, arguments: ["auth", "status", "--json"],
                workspace: workspace, environment: environment)
            let loggedIn = InstalledAIProbe.loggedIn(toClaude: auth.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: auth.status == 0 && loggedIn ? .ready : .signInRequired,
                    version: version, executable: executable,
                    models: loggedIn ? InstalledAIModel.claude : [],
                    account: loggedIn ? InstalledAIAccount.claude(statusJSON: auth.output) : nil)
            )
        case .openCode:
            let models = await InstalledAIProbe.run(
                executable: executable, arguments: ["models", "--pure", "--verbose"],
                workspace: workspace, environment: environment)
            let catalog = InstalledAIModel.openCodeCatalog(models.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: models.status == 0 && !catalog.isEmpty ? .ready : .signInRequired,
                    version: version, executable: executable, models: catalog)
            )
        case .copilot:
            // No auth subcommand beyond `--version`; a logged-in user in its config means ready.
            let configURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".copilot/config.json")
            let configData = try? Data(contentsOf: configURL)
            let signedIn: Bool = {
                guard let users = InstalledAIModel.parseCopilotConfig(configData)?["loggedInUsers"]
                    as? [Any]
                else { return false }
                return !users.isEmpty
            }()
            // The recent-models list stands in when the ACP server cannot be asked.
            var models = InstalledAIModel.copilotCatalog(configJSON: configData)
            if signedIn {
                models =
                    await InstalledAIProbe.copilotModels(
                        executable: executable, workspace: workspace, environment: environment)
                    ?? models
            }
            return (
                kind,
                InstalledAIStatus(
                    phase: signedIn ? .ready : .signInRequired,
                    version: version, executable: executable, models: signedIn ? models : [])
            )
        case .codex:
            return (kind, InstalledAIStatus(phase: .idle))
        }
    }
}

enum InstalledAIProbe {
    private static let maximumOutputBytes = 2 * 1_048_576
    private static let readChunkBytes = 64 * 1_024

    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    private final class ProcessHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func set(_ process: Process) {
            lock.lock()
            self.process = process
            let shouldTerminate = cancelled
            lock.unlock()
            if shouldTerminate { process.terminate() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let process = self.process
            lock.unlock()
            if let process, process.isRunning { process.terminate() }
        }
    }

    /// A nil `environment` inherits the app's own, as a probe with no variables set does.
    nonisolated static func run(
        executable: URL, arguments: [String], workspace: URL,
        environment: [String: String]? = nil
    ) async -> Result {
        let handle = ProcessHandle()
        return await withTaskCancellationHandler(
            operation: {
                // Detached because the read loop and the exit wait block: never a pool thread.
                await Task.detached {
                    try? FileManager.default.createDirectory(
                        at: workspace, withIntermediateDirectories: true)
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.currentDirectoryURL = workspace
                    if let environment { process.environment = environment }
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    guard let exit = try? process.runObservingExit() else {
                        return Result(status: -1, output: "")
                    }
                    handle.set(process)
                    let watchdog = Task {
                        try? await Task.sleep(for: .seconds(10))
                        if process.isRunning { process.terminate() }
                    }
                    var data = Data()
                    while data.count < Self.maximumOutputBytes {
                        let count = min(Self.readChunkBytes, Self.maximumOutputBytes - data.count)
                        guard let chunk = try? output.fileHandleForReading.read(upToCount: count),
                            !chunk.isEmpty
                        else { break }
                        data.append(chunk)
                    }
                    if data.count == Self.maximumOutputBytes, process.isRunning {
                        process.terminate()
                    }
                    exit.wait()
                    watchdog.cancel()
                    return Result(
                        status: process.terminationStatus,
                        output: String(bytes: data, encoding: .utf8) ?? "")
                }.value
            },
            onCancel: {
                handle.cancel()
            })
    }

    /// Asks Copilot's ACP server for the account's models, then selects each in turn to learn
    /// which reasoning efforts it takes: Copilot rejects an effort a model does not offer.
    nonisolated static func copilotModels(
        executable: URL, workspace: URL, environment: [String: String]?,
        timeout: Duration = .seconds(20)
    ) async -> [InstalledAIModel]? {
        let handle = ProcessHandle()
        return await withTaskCancellationHandler(
            operation: {
                await Task.detached {
                    try? FileManager.default.createDirectory(
                        at: workspace, withIntermediateDirectories: true)
                    let process = Process()
                    let stdin = Pipe()
                    let output = Pipe()
                    process.executableURL = executable
                    process.arguments = ["--acp"]
                    process.currentDirectoryURL = workspace
                    if let environment { process.environment = environment }
                    process.standardInput = stdin
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    guard let exit = try? process.runObservingExit() else { return nil }
                    handle.set(process)
                    // A child that exits before reading must fail the write, not SIGPIPE Onecast.
                    _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                    let watchdog = Task {
                        try? await Task.sleep(for: timeout)
                        if process.isRunning { process.terminate() }
                    }
                    defer {
                        try? stdin.fileHandleForWriting.close()
                        if process.isRunning { process.terminate() }
                        exit.wait()
                        watchdog.cancel()
                    }
                    var data = Data()
                    // `availableData`, not `read(upToCount:)`, which would wait for the watchdog.
                    func answer<Value>(_ parse: (String) -> Value?) -> Value? {
                        while data.count < Self.maximumOutputBytes {
                            if let value = parse(String(bytes: data, encoding: .utf8) ?? "") {
                                return value
                            }
                            let chunk = output.fileHandleForReading.availableData
                            guard !chunk.isEmpty else { return nil }
                            data.append(chunk)
                        }
                        return nil
                    }
                    func send(_ line: Data) {
                        try? stdin.fileHandleForWriting.write(contentsOf: line)
                    }
                    send(InstalledAIModel.copilotACPRequest(workspace: workspace))
                    guard let catalog = answer({ InstalledAIModel.copilotACPCatalog($0) }) else {
                        return nil
                    }
                    var models: [InstalledAIModel] = []
                    // One at a time: a selection answered early still describes the model before it.
                    for (offset, model) in catalog.models.enumerated() {
                        let requestID = 100 + offset
                        send(
                            InstalledAIModel.copilotACPSelect(
                                model: model.id, session: catalog.session, requestID: requestID))
                        guard
                            let efforts = answer({
                                InstalledAIModel.copilotACPEfforts($0, requestID: requestID)
                            })
                        else { break }
                        models.append(InstalledAIModel(id: model.id, name: model.name, efforts: efforts))
                    }
                    // A model never asked about takes no effort, which Copilot always accepts.
                    return models + catalog.models.dropFirst(models.count)
                }.value
            },
            onCancel: {
                handle.cancel()
            })
    }

    nonisolated static func version(in output: String) -> String? {
        output.firstMatch(of: #/\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?/#)
            .map { String($0.output).trimmingCharacters(in: CharacterSet(charactersIn: ".-")) }
    }

    nonisolated static func loggedIn(toClaude output: String) -> Bool {
        guard let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["loggedIn"] as? Bool == true
            || object["authenticated"] as? Bool == true
            || object["isAuthenticated"] as? Bool == true
    }

}
