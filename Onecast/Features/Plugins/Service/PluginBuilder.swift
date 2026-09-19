import CryptoKit
import Foundation

/// Why a source plugin couldn't be turned into a loadable dylib. Every payload is a plain string, so
/// the error crosses back to the main actor as a `Sendable` value.
enum PluginBuildError: LocalizedError, Sendable {
    case toolchainMissing
    case interfaceMissing
    case noSources
    case compileFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolchainMissing:
            return "No Swift toolchain found — install Xcode or the Command Line Tools to build plugins."
        case .interfaceMissing:
            return "OnecastPluginKit's module interface is missing from this build — rebuild Onecast."
        case .noSources:
            return "This plugin has no Swift sources to build."
        case .compileFailed(let log):
            return log
        }
    }
}

/// Compiles a source plugin's Swift files into a signed dylib the loader can `dlopen`, caching on the
/// source fingerprint so an unchanged plugin never recompiles. Every step is `nonisolated` and meant
/// to run off the main actor — `swiftc` and `codesign` are spawned as child processes.
enum PluginBuilder {
    /// The built, signed dylib for `install`, compiling only when the source or the framework ABI it
    /// links against has changed since the last build.
    nonisolated static func build(_ install: PluginInstall) throws -> URL {
        guard !install.sources.isEmpty else { throw PluginBuildError.noSources }
        let dir = buildDirectory(for: install)
        let dylib = dir.appendingPathComponent("lib\(install.moduleName).dylib")
        let stamp = dir.appendingPathComponent(".build-key")
        let key = try cacheKey(for: install)
        if FileManager.default.fileExists(atPath: dylib.path),
            (try? String(contentsOf: stamp, encoding: .utf8)) == key {
            return dylib
        }
        try compile(install, to: dylib)
        try? key.write(to: stamp, atomically: true, encoding: .utf8)
        return dylib
    }

    /// `build` wrapped as a `Sendable` result, so a caller can `await` it off-main and hop the
    /// outcome back to the main actor without an untyped `any Error` crossing the boundary.
    nonisolated static func buildResult(_ install: PluginInstall) -> Result<URL, PluginBuildError> {
        do {
            return .success(try build(install))
        } catch let error as PluginBuildError {
            return .failure(error)
        } catch {
            return .failure(.compileFailed(error.localizedDescription))
        }
    }

    private static func buildDirectory(for install: PluginInstall) -> URL {
        let slug = install.manifest.identifier
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let dir = AppPaths.caches()
            .appendingPathComponent("PluginBuilds", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The source fingerprint fused with the framework binary's own size and mtime, so a rebuilt app
    /// that changes the plugin ABI invalidates every cached dylib it once produced.
    private static func cacheKey(for install: PluginInstall) throws -> String {
        let binary = try interfaceFramework().appendingPathComponent("Versions/A/OnecastPluginKit")
        let values = try? binary.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let mtime = Int(values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)
        return "\(install.sourceHash)-\(size)-\(mtime)"
    }

    private static func compile(_ install: PluginInstall, to dylib: URL) throws {
        guard toolchainAvailable() else { throw PluginBuildError.toolchainMissing }
        let frameworks = try interfaceFramework().deletingLastPathComponent()
        let tmp = dylib.deletingLastPathComponent()
            .appendingPathComponent("lib\(install.moduleName).\(UUID().uuidString).tmp")

        // @executable_path in a dlopened dylib resolves against the host app's executable, so this
        // rpath points the plugin's @rpath framework dependency at the app's own Frameworks folder.
        var args = [
            "-emit-library", "-O",
            "-module-name", install.moduleName,
            "-F", frameworks.path, "-framework", "OnecastPluginKit",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            "-o", tmp.path,
        ]
        args += install.sources.map(\.path)

        // Through `xcrun`, not a resolved `swiftc` path, so the tool inherits SDKROOT and the active
        // toolchain — a bare `swiftc` can't find the standard library for the app's deployment target.
        let compiled = run("/usr/bin/xcrun", ["swiftc"] + args)
        guard compiled.status == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw PluginBuildError.compileFailed(diagnostic(compiled.output))
        }
        // Ad-hoc sign so the hardened runtime loads it — the host disables library validation.
        let signed = run("/usr/bin/codesign", ["--force", "--sign", "-", tmp.path])
        guard signed.status == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw PluginBuildError.compileFailed(diagnostic(signed.output))
        }
        // Atomic swap: a concurrent prewarm build of the same plugin never hands out a half-written
        // dylib, and the content-addressed loader maps the fresh bytes on the next open.
        if FileManager.default.fileExists(atPath: dylib.path) {
            _ = try FileManager.default.replaceItemAt(dylib, withItemAt: tmp)
        } else if (try? FileManager.default.moveItem(at: tmp, to: dylib)) == nil {
            try? FileManager.default.removeItem(at: tmp)  // lost a race; the winner's dylib stands
        }
    }

    /// Whether a Swift toolchain is installed at all, so a missing one becomes a clear message rather
    /// than a raw compiler error.
    private static func toolchainAvailable() -> Bool {
        run("/usr/bin/xcrun", ["--find", "swiftc"]).status == 0
    }

    /// The app's own embedded `OnecastPluginKit.framework`, verified to still carry the textual
    /// interface a plugin compiles against (restored into the embed by a post-build step).
    private static func interfaceFramework() throws -> URL {
        guard let frameworks = Bundle.main.privateFrameworksURL else {
            throw PluginBuildError.interfaceMissing
        }
        let framework = frameworks.appendingPathComponent("OnecastPluginKit.framework")
        let modules = framework.appendingPathComponent("Modules/OnecastPluginKit.swiftmodule")
        let hasInterface =
            (try? FileManager.default.contentsOfDirectory(at: modules, includingPropertiesForKeys: nil))?
            .contains { $0.pathExtension == "swiftinterface" } ?? false
        guard hasInterface else { throw PluginBuildError.interfaceMissing }
        return framework
    }

    /// Runs a tool to completion, draining its combined output first so a large compiler diagnostic
    /// never fills the pipe buffer and deadlocks the child.
    private static func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    private static func diagnostic(_ log: String) -> String {
        let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "The plugin failed to build." }
        let limit = 1500
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
    }
}
