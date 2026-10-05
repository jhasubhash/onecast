import CryptoKit
import Foundation
import OnecastPluginKit

enum PluginLoadError: LocalizedError {
    case openFailed(String)
    case missingEntry(name: String, symbol: String)
    case wrongType(name: String, protocolName: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Couldn't load the plugin: \(message)"
        case .missingEntry(let name, let symbol):
            return "\(name) has no \(symbol) entry point — rebuild it against OnecastPluginKit."
        case .wrongType(let name, let protocolName):
            return "\(name) doesn't conform to \(protocolName) — check it's linked against this app's framework."
        }
    }
}

/// Loads a plugin's freshly built dylib and hands back its instance.
///
/// dlopen caches by path and a Swift dylib can't be safely dlclosed while its types are still
/// referenced, so opening a *rebuilt* plugin from its canonical path would return the stale image
/// and force a relaunch. Instead we map a **content-addressed copy** in the temp dir: unchanged
/// bytes reuse the one mapping, a rebuild maps the new bytes on the next open (no relaunch), and
/// older copies of that plugin are swept so at most one file per plugin lingers on disk. dlopen
/// still never closes — only a real rebuild costs one more small mapping, reclaimed when the app
/// quits.
enum PluginLoader {
    @MainActor
    static func load(_ install: PluginInstall, builtDylib: URL) throws -> any OnecastPlugin {
        let symbol = try entry(of: install, dylib: builtDylib)
        let create = unsafeBitCast(symbol, to: OnecastPluginCreate.self)
        guard let plugin = OnecastPluginRuntime.consume(create()) else {
            throw PluginLoadError.wrongType(
                name: install.displayName, protocolName: install.kind.protocolName)
        }
        return plugin
    }

    /// A DockWidget dylib's entry point, mapped once per build; the host calls it per instance.
    @MainActor
    static func dockWidgetFactory(
        _ install: DockWidgetInstall, builtDylib: URL
    ) throws -> DockWidgetFactory {
        let symbol = try entry(of: install, dylib: builtDylib)
        return DockWidgetFactory(
            name: install.manifest.name, create: unsafeBitCast(symbol, to: OnecastDockWidgetCreate.self))
    }

    /// Maps the dylib and looks up the kind's `@_cdecl` symbol.
    private static func entry(of source: some PluginSource, dylib: URL) throws -> UnsafeMutableRawPointer {
        let path = stagedCopy(source, dylib: dylib) ?? dylib.path
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw PluginLoadError.openFailed(dlerror().map { String(cString: $0) } ?? "unknown error")
        }
        guard let symbol = dlsym(handle, source.kind.entrySymbol) else {
            throw PluginLoadError.missingEntry(name: source.displayName, symbol: source.kind.entrySymbol)
        }
        return symbol
    }

    /// Copies the built dylib to `…/onecast-plugin-<identifier>-<sha>.dylib`, reusing an identical
    /// existing copy and sweeping older ones for the same plugin. Returns nil on any failure, so
    /// the caller falls back to the canonical path. The ad-hoc signature is content-based, so the
    /// copy stays valid, and `@rpath/OnecastPluginKit.framework` resolves via the host executable
    /// regardless of where the dylib sits.
    private static func stagedCopy(_ source: some PluginSource, dylib: URL) -> String? {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: dylib) else { return nil }
        let sha = SHA256.hash(data: data).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        let slug =
            source.id
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let dir = fm.temporaryDirectory
        let prefix = "\(source.kind.stagedPrefix)\(slug)-"
        let dest = dir.appendingPathComponent("\(prefix)\(sha).dylib")

        if !fm.fileExists(atPath: dest.path) {
            do { try data.write(to: dest, options: .atomic) } catch { return nil }
        }
        if let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            // Compare by filename: `contentsOfDirectory` resolves /var → /private/var, so the just-
            // written `dest` is byte-identical yet URL-unequal, and a naive `url != dest` sweeps it.
            for url in entries
            where url.lastPathComponent.hasPrefix(prefix)
                && url.lastPathComponent != dest.lastPathComponent {
                try? fm.removeItem(at: url)  // stale copy of this plugin; a live mapping persists
            }
        }
        return dest.path
    }
}
