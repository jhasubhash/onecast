import Foundation

@main
struct ScopesTest {
    static func main() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("onecast-scopes-\(UUID().uuidString)")

        // Injected rather than read, so the walk and the path arithmetic never depend on the machine.
        let home = URL(fileURLWithPath: "/Users/fixture")
        let homePath = home.path

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS \(description)")
            } else {
                print("FAIL \(description)")
                failures += 1
            }
        }

        func makeDir(_ url: URL) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Two direct apps, a non-app file, a hidden app, one nested app, one two-deep nested app.
        let apps = root.appendingPathComponent("Apps")
        makeDir(apps.appendingPathComponent("Alpha.app"))
        makeDir(apps.appendingPathComponent("Beta.app"))
        makeDir(apps.appendingPathComponent("Notes.txt"))
        makeDir(apps.appendingPathComponent(".Hidden.app"))
        let vendor = apps.appendingPathComponent("Vendor")
        makeDir(vendor.appendingPathComponent("Nested.app"))
        let deep = vendor.appendingPathComponent("Deeper")
        makeDir(deep.appendingPathComponent("TooDeep.app"))

        let found = AppBundleScanner.appBundles(in: [apps.path], homeDirectory: home)
            .map(\.lastPathComponent)
        check(
            "direct and one-level-nested .app children are indexed",
            Set(found) == ["Alpha.app", "Beta.app", "Nested.app"])
        check("non-app children are skipped", !found.contains("Notes.txt"))
        check("hidden bundles are skipped", !found.contains(".Hidden.app"))
        check("bundles nested two levels deep are not indexed", !found.contains("TooDeep.app"))
        check(
            "a deeply nested folder works as its own scope",
            AppBundleScanner.appBundles(in: [deep.path], homeDirectory: home)
                .map(\.lastPathComponent) == ["TooDeep.app"])

        // A scope may be a single bundle: that is how Finder ships as a default.
        check(
            "an .app scope is indexed directly",
            AppBundleScanner.appBundles(
                in: [apps.appendingPathComponent("Alpha.app").path], homeDirectory: home)
                .map(\.lastPathComponent) == ["Alpha.app"])
        check(
            "a missing .app scope yields nothing",
            AppBundleScanner.appBundles(
                in: [apps.appendingPathComponent("Gone.app").path], homeDirectory: home).isEmpty)
        check(
            "a missing directory scope is skipped without failing the rest",
            AppBundleScanner.appBundles(
                in: [root.appendingPathComponent("Nope").path, deep.path], homeDirectory: home)
                .map(\.lastPathComponent) == ["TooDeep.app"])

        // Xcode ships Instruments and Simulator inside its own bundle.
        let tools = root.appendingPathComponent("Tools")
        let xcode = tools.appendingPathComponent("Xcode.app")
        makeDir(xcode.appendingPathComponent("Contents/Applications/Instruments.app"))
        makeDir(xcode.appendingPathComponent("Contents/Developer/Applications/Simulator.app"))
        makeDir(xcode.appendingPathComponent("Contents/Frameworks/Helper.app"))
        let embedded = Set(
            AppBundleScanner.appBundles(in: [tools.path], homeDirectory: home)
                .map(\.lastPathComponent))
        check(
            "apps embedded in a bundle's application folders are indexed",
            embedded == ["Xcode.app", "Instruments.app", "Simulator.app"])
        check(
            "an .app scope also yields its embedded apps",
            Set(
                AppBundleScanner.appBundles(in: [xcode.path], homeDirectory: home)
                    .map(\.lastPathComponent)) == embedded)

        check(
            "scopes are scanned in order",
            AppBundleScanner.appBundles(in: [deep.path, apps.path], homeDirectory: home)
                .map(\.lastPathComponent).first == "TooDeep.app")
        check(
            "overlapping scopes yield each app once, at its first scope's position",
            AppBundleScanner.appBundles(
                in: [xcode.path, tools.path, deep.path, vendor.path], homeDirectory: home)
                .map(\.lastPathComponent)
                == ["Xcode.app", "Instruments.app", "Simulator.app", "TooDeep.app", "Nested.app"])

        check(
            "expand resolves a tilde",
            SearchScopes.expand("~/Applications", homeDirectory: home) == homePath + "/Applications")
        check(
            "abbreviate restores the tilde",
            SearchScopes.abbreviate(homePath + "/Applications", homeDirectory: home)
                == "~/Applications")
        check(
            "tilde survives a round trip",
            SearchScopes.abbreviate(
                SearchScopes.expand("~/Applications", homeDirectory: home), homeDirectory: home)
                == "~/Applications")
        check(
            "expand leaves an absolute path alone",
            SearchScopes.expand("/Applications", homeDirectory: home) == "/Applications")
        check(
            "a trailing slash is trimmed",
            SearchScopes.abbreviate("/Applications/", homeDirectory: home) == "/Applications")
        check("root survives trimming", SearchScopes.abbreviate("/", homeDirectory: home) == "/")

        check(
            "normalize dedups after abbreviating",
            SearchScopes.normalize(
                ["/Applications", "/Applications/", homePath + "/Applications", "~/Applications"],
                homeDirectory: home)
                == ["/Applications", "~/Applications"])
        check(
            "normalize preserves order",
            SearchScopes.normalize(["/B", "/A"], homeDirectory: home) == ["/B", "/A"])
        check(
            "normalize drops blanks",
            SearchScopes.normalize(["  ", "/A"], homeDirectory: home) == ["/A"])
        check(
            "defaults are already normalized",
            SearchScopes.normalize(SearchScopes.defaults, homeDirectory: home)
                == SearchScopes.defaults)

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
