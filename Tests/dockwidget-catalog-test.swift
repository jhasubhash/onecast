import Foundation

@main
@MainActor
struct DockWidgetCatalogTests {
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
        manifestDefaultsWhenOnlyRequiredKeysArePresent()
        manifestDecodesEveryKey()
        manifestRequiresNameAndIdentifier()
        manifestIgnoresUnknownKeys()
        manifestDropsUnknownSizes()
        manifestFallsBackWhenSizesAreMalformed()
        manifestBlankIconAndCategoryUseDefaults()
        manifestRoundTripsThroughCodable()
        identifierRules()
        installDerivesIDAndModuleName()
        scanReturnsOnlyWidgetsWithSources()
        scanSkipsUnusableIdentifiers()
        scanKeepsFirstOfDuplicateIdentifiers()
        scanGathersNestedSources()
        scanFingerprintTracksSourceEdits()
        scanFingerprintTracksAddedSources()
        scanSortsByNameCaseInsensitive()
        scanOnMissingRootIsEmptyNotAnError()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Manifest

    /// A widget author writes only `name` and `identifier`; everything else reads as the kit's own
    /// `DockWidgetMetadata` defaults, so a manifest and a compiled widget agree.
    static func manifestDefaultsWhenOnlyRequiredKeysArePresent() {
        let json = Data(#"{"name":"Bare","identifier":"com.acme.bare"}"#.utf8)
        guard let decoded = try? JSONDecoder().decode(DockWidgetManifest.self, from: json) else {
            return expect(false, "a manifest with only the required keys failed to decode")
        }
        expect(decoded.subtitle == "", "an absent subtitle is empty")
        expect(decoded.icon == "square.grid.2x2", "an absent icon is the kit's default symbol")
        expect(decoded.category == "Other", "an absent category is Other")
        expect(decoded.sizes == [.compact], "absent sizes mean a compact widget")
        expect(decoded.module == nil, "an absent module stays nil so it is derived from the name")
        expect(decoded.preferences == nil, "absent preferences stay nil")
    }

    static func manifestDecodesEveryKey() {
        let json = Data(#"""
            {"name":"Clock","identifier":"com.acme.clock","subtitle":"Tells time","icon":"clock",
             "category":"Time","sizes":["wide","compact","expanded"],"module":"ClockWidget",
             "preferences":[
               {"name":"zone","title":"Zone","type":"dropdown","default":"utc",
                "options":[{"title":"UTC","value":"utc"},{"title":"Local","value":"local"}]},
               {"name":"seconds","title":"Seconds","type":"checkbox","default":true}]}
            """#.utf8)
        guard let decoded = try? JSONDecoder().decode(DockWidgetManifest.self, from: json) else {
            return expect(false, "a complete manifest failed to decode")
        }
        expect(decoded.subtitle == "Tells time" && decoded.icon == "clock", "subtitle and icon decode")
        expect(decoded.category == "Time", "category decodes")
        expect(decoded.sizes == [.wide, .compact, .expanded], "sizes keep their order: the first is the default")
        expect(decoded.module == "ClockWidget", "module decodes")
        expect(decoded.preferences?.map(\.name) == ["zone", "seconds"], "preferences keep their order")
        expect(decoded.preferences?[0].registeredDefault as? String == "utc", "a dropdown default registers as text")
        expect(decoded.preferences?[1].registeredDefault as? Bool == true, "a checkbox default registers as a Bool")
    }

    static func manifestRequiresNameAndIdentifier() {
        let noIdentifier = Data(#"{"name":"X"}"#.utf8)
        let noName = Data(#"{"identifier":"com.acme.x"}"#.utf8)
        expect(
            (try? JSONDecoder().decode(DockWidgetManifest.self, from: noIdentifier)) == nil,
            "a manifest without an identifier is not a widget")
        expect(
            (try? JSONDecoder().decode(DockWidgetManifest.self, from: noName)) == nil,
            "a manifest without a name is not a widget")
    }

    static func manifestIgnoresUnknownKeys() {
        let json = Data(#"{"name":"X","identifier":"com.acme.x","futureKey":{"a":1},"sizes":["wide"]}"#.utf8)
        let decoded = try? JSONDecoder().decode(DockWidgetManifest.self, from: json)
        expect(decoded?.sizes == [.wide], "an unknown key neither fails the manifest nor hides the rest")
    }

    static func manifestDropsUnknownSizes() {
        let json = Data(#"{"name":"X","identifier":"id","sizes":["huge","wide","Wide","wide","compact"]}"#.utf8)
        let decoded = try? JSONDecoder().decode(DockWidgetManifest.self, from: json)
        expect(decoded?.sizes == [.wide, .compact], "unknown sizes are dropped, repeats collapse, case matters")

        let onlyUnknown = Data(#"{"name":"X","identifier":"id","sizes":["huge","gigantic"]}"#.utf8)
        expect(
            (try? JSONDecoder().decode(DockWidgetManifest.self, from: onlyUnknown))?.sizes == [.compact],
            "a widget whose every size is unknown is still compact")
    }

    /// A malformed `sizes` must not lose a widget its row, only its size choice.
    static func manifestFallsBackWhenSizesAreMalformed() {
        let notAnArray = Data(#"{"name":"X","identifier":"id","sizes":"wide"}"#.utf8)
        let empty = Data(#"{"name":"X","identifier":"id","sizes":[]}"#.utf8)
        expect(
            (try? JSONDecoder().decode(DockWidgetManifest.self, from: notAnArray))?.sizes == [.compact],
            "sizes that is not an array falls back to compact")
        expect(
            (try? JSONDecoder().decode(DockWidgetManifest.self, from: empty))?.sizes == [.compact],
            "an empty sizes list falls back to compact")
    }

    static func manifestBlankIconAndCategoryUseDefaults() {
        let json = Data(#"{"name":"X","identifier":"id","icon":"  ","category":""}"#.utf8)
        let decoded = try? JSONDecoder().decode(DockWidgetManifest.self, from: json)
        expect(decoded?.icon == DockWidgetManifest.defaultIcon, "a blank icon reads as the default symbol")
        expect(decoded?.category == DockWidgetManifest.defaultCategory, "an empty category reads as Other")
    }

    static func manifestRoundTripsThroughCodable() {
        let manifest = DockWidgetManifest(
            name: "Clock", identifier: "com.acme.clock", subtitle: "Time", icon: "clock",
            category: "Time", sizes: [.wide, .compact], module: "Clk",
            preferences: [PluginPreference(name: "zone", title: "Zone", defaultValue: .string("utc"))])
        guard
            let data = try? JSONEncoder().encode(manifest),
            let decoded = try? JSONDecoder().decode(DockWidgetManifest.self, from: data)
        else { return expect(false, "manifest failed to round-trip through Codable") }
        expect(decoded == manifest, "a manifest survives an encode/decode round-trip intact")
    }

    // MARK: - Identity

    /// The identifier is what a dock item stores, so a blank one or a first-party one can't be a key.
    static func identifierRules() {
        func manifest(_ id: String) -> DockWidgetManifest { DockWidgetManifest(name: "X", identifier: id) }
        expect(manifest("com.acme.x").hasUsableIdentifier, "a reverse-DNS identifier is usable")
        expect(!manifest("").hasUsableIdentifier, "an empty identifier is unusable")
        expect(!manifest("   ").hasUsableIdentifier, "a blank identifier is unusable")
        expect(!manifest("builtin.time").hasUsableIdentifier, "a first-party id can't be claimed")
        expect(manifest("Builtin.x").hasUsableIdentifier, "the reserved prefix is case-sensitive, as ids are")
    }

    static func installDerivesIDAndModuleName() {
        let dir = URL(fileURLWithPath: "/tmp/dockwidgets/clock", isDirectory: true)
        let derived = DockWidgetInstall(
            manifest: DockWidgetManifest(name: "World Clock", identifier: "com.acme.clock"),
            directory: dir, sources: [], sourceHash: "abc")
        expect(derived.id == "com.acme.clock", "an install's id is its manifest identifier")
        expect(derived.moduleName == "WorldClock", "the module name derives from the display name")

        let explicit = DockWidgetInstall(
            manifest: DockWidgetManifest(name: "World Clock", identifier: "id", module: "Clk"),
            directory: dir, sources: [], sourceHash: "")
        expect(explicit.moduleName == "Clk", "an explicit manifest module overrides the derivation")
    }

    // MARK: - Scan

    static func scanReturnsOnlyWidgetsWithSources() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        writeInstall(root, folder: "good", identifier: "com.acme.good", source: "Good.swift")
        // A manifest with no `.swift` source is a half-copied install and must not appear.
        writeInstall(root, folder: "nosource", identifier: "com.acme.nosource", source: nil)
        let noManifest = root.appendingPathComponent("nomanifest", isDirectory: true)
        try? FileManager.default.createDirectory(at: noManifest, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: noManifest.appendingPathComponent("Orphan.swift").path, contents: Data())
        // A manifest that does not decode is not a widget either.
        let broken = root.appendingPathComponent("broken", isDirectory: true)
        try? FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try? Data("{not json".utf8).write(to: broken.appendingPathComponent("manifest.json"))
        FileManager.default.createFile(
            atPath: broken.appendingPathComponent("B.swift").path, contents: Data("// b".utf8))
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("stray.txt").path, contents: Data("hi".utf8))

        let installs = DockWidgetCatalog.scan(root: root)
        expect(installs.map(\.id) == ["com.acme.good"], "scan returns only the complete widget")
        expect(installs.first?.sources.count == 1, "the install carries the source the compiler builds")
    }

    static func scanSkipsUnusableIdentifiers() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        writeInstall(root, folder: "ok", identifier: "com.acme.ok", source: "A.swift")
        writeInstall(root, folder: "reserved", identifier: "builtin.clock", source: "B.swift")
        writeInstall(root, folder: "blank", identifier: " ", source: "C.swift")

        expect(
            DockWidgetCatalog.scan(root: root).map(\.id) == ["com.acme.ok"],
            "a first-party or blank identifier never reaches the catalog")
    }

    /// Two folders claiming one identifier would make a dock item ambiguous: the first by name wins.
    static func scanKeepsFirstOfDuplicateIdentifiers() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        writeInstall(root, folder: "z", identifier: "com.acme.same", source: "Z.swift", name: "Zed")
        writeInstall(root, folder: "a", identifier: "com.acme.same", source: "A.swift", name: "Alpha")

        let installs = DockWidgetCatalog.scan(root: root)
        expect(installs.count == 1, "a duplicate identifier appears once")
        expect(installs.first?.manifest.name == "Alpha", "the first by name wins")
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

        let names = Set(DockWidgetCatalog.scan(root: root).first?.sources.map(\.lastPathComponent) ?? [])
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
        let before = DockWidgetCatalog.scan(root: root).first?.sourceHash

        try? Data("// version two, longer".utf8).write(to: source)
        let after = DockWidgetCatalog.scan(root: root).first?.sourceHash

        expect(before != nil && after != nil, "both scans found the widget")
        expect(before != after, "a source edit changes the fingerprint the builder caches on")
    }

    static func scanFingerprintTracksAddedSources() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let dir = root.appendingPathComponent("grow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writeManifest(dir, identifier: "com.acme.grow", name: "Grow")
        try? Data("// a".utf8).write(to: dir.appendingPathComponent("A.swift"))
        let before = DockWidgetCatalog.scan(root: root).first?.sourceHash

        try? Data("// b".utf8).write(to: dir.appendingPathComponent("B.swift"))
        let after = DockWidgetCatalog.scan(root: root).first?.sourceHash

        expect(before != after, "adding a source file changes the fingerprint")
    }

    static func scanSortsByNameCaseInsensitive() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        writeInstall(root, folder: "c", identifier: "id.cherry", source: "C.swift", name: "cherry")
        writeInstall(root, folder: "a", identifier: "id.apple", source: "A.swift", name: "Apple")
        writeInstall(root, folder: "b", identifier: "id.banana", source: "B.swift", name: "banana")

        expect(
            DockWidgetCatalog.scan(root: root).map(\.manifest.name) == ["Apple", "banana", "cherry"],
            "installs sort case-insensitively by name")
    }

    static func scanOnMissingRootIsEmptyNotAnError() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("onecast-dockwidget-missing-\(UUID().uuidString)", isDirectory: true)
        expect(DockWidgetCatalog.scan(root: missing).isEmpty, "scanning a missing root yields no installs")
    }

    // MARK: - Fixtures

    static func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onecast-dockwidget-catalog-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writeManifest(_ dir: URL, identifier: String, name: String) {
        let manifest = DockWidgetManifest(name: name, identifier: identifier)
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
