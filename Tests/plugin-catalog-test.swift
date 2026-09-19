import Foundation

@main
@MainActor
struct PluginCatalogTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        manifestRoundTripsThroughCodable()
        manifestDecodesWithoutOptionalKeys()
        installDerivesEntryIDAndModuleName()
        moduleNameSanitizesDisplayName()
        moduleNameFromManifestWins()
        identifierFromEntryIDRoundTrips()
        identifierRejectsNonPluginEntryIDs()
        scanReturnsOnlyPluginsWithSources()
        scanGathersNestedSources()
        scanFingerprintTracksSourceEdits()
        scanSortsByNameCaseInsensitive()
        scanOnMissingRootIsEmptyNotAnError()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Manifest

    static func manifestRoundTripsThroughCodable() {
        let manifest = PluginManifest(
            name: "Jira", identifier: "com.acme.jira", subtitle: "Issues", icon: "ticket",
            module: "JiraPlugin")
        guard
            let data = try? JSONEncoder().encode(manifest),
            let decoded = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else { return expect(false, "manifest failed to round-trip through Codable") }
        expect(decoded == manifest, "a manifest survives an encode/decode round-trip intact")
    }

    /// A manifest that omits every optional key must still decode — a plugin author writes only
    /// `name` and `identifier`, and the module name is derived when absent.
    static func manifestDecodesWithoutOptionalKeys() {
        let json = Data(#"{"name":"Bare","identifier":"com.acme.bare"}"#.utf8)
        guard let decoded = try? JSONDecoder().decode(PluginManifest.self, from: json) else {
            return expect(false, "a manifest missing optional keys failed to decode")
        }
        expect(decoded.subtitle == nil, "an absent subtitle decodes as nil")
        expect(decoded.icon == nil, "an absent icon decodes as nil")
        expect(decoded.module == nil, "an absent module decodes as nil")
        expect(decoded.name == "Bare", "the required keys decode")
    }

    // MARK: - Install identity

    static func installDerivesEntryIDAndModuleName() {
        let dir = URL(fileURLWithPath: "/tmp/plugins/jira", isDirectory: true)
        let manifest = PluginManifest(
            name: "Jira", identifier: "com.acme.jira", subtitle: nil, icon: nil, module: nil)
        let install = PluginInstall(
            manifest: manifest, directory: dir,
            sources: [dir.appendingPathComponent("Jira.swift")], sourceHash: "abc")
        expect(install.id == "com.acme.jira", "an install's id is its manifest identifier")
        expect(install.entryID == "plugin:com.acme.jira", "the entry id namespaces the identifier")
        expect(install.moduleName == "Jira", "the module name derives from the display name")
    }

    static func moduleNameSanitizesDisplayName() {
        expect(
            PluginInstall.moduleName(from: "Stock Quotes") == "StockQuotes",
            "spaces and punctuation are stripped from a derived module name")
        expect(
            PluginInstall.moduleName(from: "3D Tools") == "Plugin3DTools",
            "a digit-first name is prefixed so it stays a legal Swift identifier")
    }

    static func moduleNameFromManifestWins() {
        let manifest = PluginManifest(
            name: "Stock Quotes", identifier: "id", subtitle: nil, icon: nil, module: "Ticker")
        let install = PluginInstall(
            manifest: manifest, directory: URL(fileURLWithPath: "/tmp/x"),
            sources: [], sourceHash: "")
        expect(install.moduleName == "Ticker", "an explicit manifest module overrides the derivation")
    }

    static func identifierFromEntryIDRoundTrips() {
        let manifest = PluginManifest(
            name: "X", identifier: "com.acme.x", subtitle: nil, icon: nil, module: nil)
        let install = PluginInstall(
            manifest: manifest, directory: URL(fileURLWithPath: "/tmp/x"),
            sources: [], sourceHash: "")
        expect(
            PluginInstall.identifier(fromEntryID: install.entryID) == "com.acme.x",
            "the entry id round-trips back to the identifier")
    }

    static func identifierRejectsNonPluginEntryIDs() {
        expect(
            PluginInstall.identifier(fromEntryID: "assistant:123") == nil,
            "another feature's entry id is not read as a plugin's")
        expect(
            PluginInstall.identifier(fromEntryID: "com.acme.x") == nil,
            "a bare identifier without the prefix is not a plugin entry id")
        expect(
            PluginInstall.identifier(fromEntryID: "Plugin:x") == nil,
            "the prefix match is case-sensitive")
        expect(
            PluginInstall.identifier(fromEntryID: "plugin:") == "",
            "the prefix alone yields an empty identifier, not nil")
    }

    // MARK: - Scan

    static func scanReturnsOnlyPluginsWithSources() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        writeInstall(root, folder: "good", identifier: "com.acme.good", source: "Good.swift")
        // A manifest with no `.swift` source is a half-copied install and must not appear.
        writeInstall(root, folder: "nosource", identifier: "com.acme.nosource", source: nil)
        // A folder with sources but no manifest cannot be surfaced as a row.
        let noManifest = root.appendingPathComponent("nomanifest", isDirectory: true)
        try? FileManager.default.createDirectory(at: noManifest, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: noManifest.appendingPathComponent("Orphan.swift").path, contents: Data())
        // A plain file sitting at the root is not a plugin directory.
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("stray.txt").path, contents: Data("hi".utf8))

        let installs = PluginCatalog.scan(root: root)
        expect(installs.count == 1, "scan returns only the one plugin that has a source")
        expect(
            installs.first?.manifest.identifier == "com.acme.good",
            "the surfaced install is the complete one")
        expect(
            installs.first?.sources.count == 1,
            "the install carries the source the compiler will build")
    }

    /// A source may sit at any depth; the compiler's own `build`/`.build` output is never a source.
    static func scanGathersNestedSources() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let dir = root.appendingPathComponent("nested", isDirectory: true)
        let sub = dir.appendingPathComponent("Sources/Deep", isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        writeManifest(dir, identifier: "com.acme.nested", name: "Nested")
        FileManager.default.createFile(
            atPath: sub.appendingPathComponent("A.swift").path, contents: Data("//a".utf8))
        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("B.swift").path, contents: Data("//b".utf8))
        let buildDir = dir.appendingPathComponent("build", isDirectory: true)
        try? FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: buildDir.appendingPathComponent("Stale.swift").path, contents: Data())

        let install = PluginCatalog.scan(root: root).first
        let names = Set(install?.sources.map(\.lastPathComponent) ?? [])
        expect(names == ["A.swift", "B.swift"], "sources are gathered recursively, skipping build/")
    }

    /// Editing a source must reshape the fingerprint, or a rebuild would never fire for the edit.
    static func scanFingerprintTracksSourceEdits() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let dir = root.appendingPathComponent("edit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writeManifest(dir, identifier: "com.acme.edit", name: "Edit")
        let source = dir.appendingPathComponent("Edit.swift")
        try? Data("// v1".utf8).write(to: source)
        let before = PluginCatalog.scan(root: root).first?.sourceHash

        try? Data("// version two, longer".utf8).write(to: source)
        let after = PluginCatalog.scan(root: root).first?.sourceHash

        expect(before != nil && after != nil, "both scans found the plugin")
        expect(before != after, "a source edit changes the fingerprint the builder caches on")
    }

    static func scanSortsByNameCaseInsensitive() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        writeInstall(root, folder: "c", identifier: "id.cherry", source: "C.swift", name: "cherry")
        writeInstall(root, folder: "a", identifier: "id.apple", source: "A.swift", name: "Apple")
        writeInstall(root, folder: "b", identifier: "id.banana", source: "B.swift", name: "banana")

        let names = PluginCatalog.scan(root: root).map(\.manifest.name)
        expect(names == ["Apple", "banana", "cherry"], "installs sort case-insensitively by name")
    }

    static func scanOnMissingRootIsEmptyNotAnError() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("onecast-plugin-missing-\(UUID().uuidString)", isDirectory: true)
        expect(PluginCatalog.scan(root: missing).isEmpty, "scanning a missing root yields no installs")
    }

    // MARK: - Fixtures

    static func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onecast-plugin-catalog-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writeManifest(_ dir: URL, identifier: String, name: String) {
        let manifest = PluginManifest(
            name: name, identifier: identifier, subtitle: nil, icon: nil, module: nil)
        let data = try? JSONEncoder().encode(manifest)
        try? data?.write(to: dir.appendingPathComponent("manifest.json"))
    }

    static func writeInstall(
        _ root: URL, folder: String, identifier: String, source: String?, name: String? = nil
    ) {
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writeManifest(dir, identifier: identifier, name: name ?? folder)
        if let source {
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent(source).path, contents: Data("// x".utf8))
        }
    }
}
