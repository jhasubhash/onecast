import Foundation

@main
@MainActor
struct DocksTests {
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

    static func near(_ a: CGFloat, _ b: CGFloat, _ message: String) {
        expect(abs(a - b) < 0.001, "\(message) (got \(a), wanted \(b))")
    }

    static func main() {
        urlParsesEachVerb()
        urlUnifiesHostAndPathForms()
        urlKeepsEncodedSlashInsideAName()
        urlRejectsMalformedLinks()
        urlIgnoresOtherSchemesAndHosts()
        resolveMatchesUUIDThenName()
        entryIDsRoundTripAndStayDisjoint()
        launcherTitleFollowsVisibility()
        sanitizeRepairsDocks()
        sanitizeRepairsReferences()
        sanitizeDropsDuplicates()
        decodingToleratesMissingKeys()
        customIconsRoundTripAndOldConfigsDecode()
        arrangeGroupsPinnedRunningAndTrailing()
        arrangeRespectsContentOptions()
        arrangeMatchesAppsByBundleThenPath()
        moveReordersBeforeDestination()
        extentsAndLengths()
        frameHugsEdgeAndClampsAlignment()
        hiddenFrameAndRevealZoneFollowEdge()
        magnificationFallsOffWithDistance()
        layoutSteppingWraps()
        storeActivatesSetupAndPersists()
        storeNamesStayUnique()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - DockURL

    static func parse(_ string: String) -> DockURL? {
        URL(string: string).flatMap(DockURL.parse)
    }

    static func urlParsesEachVerb() {
        expect(parse("onecast://dock/setup/Work") == .setup("Work"), "setup parses by name")
        expect(parse("onecast://dock/toggle/Main") == .toggle("Main"), "toggle parses by name")
        expect(
            parse("onecast://dock/layout/Main/Evening") == .layout(dock: "Main", layout: "Evening"),
            "layout parses a dock and its layout")
        let id = UUID().uuidString
        expect(parse("onecast://dock/setup/\(id)") == .setup(id), "a UUID is carried verbatim")
        expect(
            parse("onecast://dock/setup/Deep%20Work") == .setup("Deep Work"),
            "percent-encoding decodes")
        expect(parse("onecast://DOCK/SETUP/Work") == .setup("Work"), "host and verb ignore case")
        expect(parse("onecast://dock/setup/Work/") == .setup("Work"), "a trailing slash is ignored")
        expect(
            parse("onecast://dock/setup/Work?from=focus") == .setup("Work"),
            "a query string is not part of the name")
    }

    static func urlUnifiesHostAndPathForms() {
        expect(parse("onecast:/dock/setup/Work") == .setup("Work"), "no authority still parses")
        expect(parse("onecast:///dock/toggle/Main") == .toggle("Main"), "empty authority parses")
    }

    static func urlKeepsEncodedSlashInsideAName() {
        expect(
            parse("onecast://dock/setup/Work%2FHome") == .setup("Work/Home"),
            "an encoded slash stays in the name")
        expect(
            parse("onecast://dock/layout/A%2FB/C") == .layout(dock: "A/B", layout: "C"),
            "an encoded slash stays in a dock name")
    }

    static func urlRejectsMalformedLinks() {
        for bad in [
            "onecast://dock", "onecast://dock/setup", "onecast://dock/setup/a/b",
            "onecast://dock/toggle", "onecast://dock/layout/Main", "onecast://dock/layout/a/b/c",
            "onecast://dock/frobnicate/x", "onecast://dock/setup/%20", "onecast://dock/layout//x",
        ] {
            expect(parse(bad) == nil, "\(bad) is not a dock action")
        }
        let claimed = URL(string: "onecast://dock/frobnicate/x")!
        expect(DockURL.claims(claimed), "a malformed dock link is still claimed, so it is reported")
    }

    static func urlIgnoresOtherSchemesAndHosts() {
        let foreign = [
            "raycast://dock/setup/Work", "https://dock/setup/Work",
            "onecast://extensions/a/b/c", "onecast://window-layout/abc",
        ]
        for string in foreign {
            let url = URL(string: string)!
            expect(!DockURL.claims(url), "\(string) is not claimed")
            expect(DockURL.parse(url) == nil, "\(string) does not parse")
        }
    }

    static func resolveMatchesUUIDThenName() {
        let work = UUID()
        let play = UUID()
        let candidates = [(id: work, name: "Work"), (id: play, name: "Café")]
        expect(DockURL.resolve(play.uuidString, among: candidates) == play, "a UUID resolves")
        expect(
            DockURL.resolve(play.uuidString.lowercased(), among: candidates) == play,
            "a lowercase UUID resolves")
        expect(DockURL.resolve(UUID().uuidString, among: candidates) == nil, "an unknown UUID misses")
        expect(DockURL.resolve("work", among: candidates) == work, "names ignore case")
        expect(DockURL.resolve("  Work \n", among: candidates) == work, "names are trimmed")
        expect(DockURL.resolve("cafe", among: candidates) == play, "names ignore accents")
        expect(DockURL.resolve("Nope", among: candidates) == nil, "an unknown name misses")
        let twin = UUID()
        expect(
            DockURL.resolve("Work", among: candidates + [(id: twin, name: "work")]) == work,
            "a duplicate name resolves to the first")
        expect(DockURL.resolve("Work", among: []) == nil, "nothing to resolve against")
    }

    // MARK: - Entry ids

    static func entryIDsRoundTripAndStayDisjoint() {
        let setup = DockSetup(name: "Work")
        let dock = CustomDock(name: "Main")
        expect(DockSetup.id(fromEntryID: setup.entryID) == setup.id, "a setup id round-trips")
        expect(CustomDock.id(fromEntryID: dock.entryID) == dock.id, "a dock id round-trips")
        expect(CustomDock.id(fromEntryID: setup.entryID) == nil, "a setup id is not a dock id")
        expect(DockSetup.id(fromEntryID: dock.entryID) == nil, "a dock id is not a setup id")
        expect(DockSetup.id(fromEntryID: "dock-setup:nope") == nil, "a malformed id is rejected")
        expect(setup.entryID == setup.entryID.lowercased(), "ids are written lowercase")
    }

    static func launcherTitleFollowsVisibility() {
        var dock = CustomDock(name: "Main", isVisible: true)
        expect(dock.launcherTitle == "Hide Main", "a shown dock offers hiding")
        dock.isVisible = false
        expect(dock.launcherTitle == "Show Main", "a hidden dock offers showing")
    }

    // MARK: - DockConfiguration

    static func sanitizeRepairsDocks() {
        var dock = CustomDock(name: "  Main  ")
        dock.placement.alignment = 4
        dock.appearance.tileSize = 999
        dock.appearance.magnifiedSize = 10
        dock.layouts = []
        var blank = CustomDock(name: "   ")
        blank.appearance.tileSize = 30
        blank.appearance.magnifiedSize = 20
        var configuration = DockConfiguration()
        configuration.docks = [dock, blank]
        configuration.sanitize()
        expect(configuration.docks[0].name == "Main", "a name is trimmed")
        expect(configuration.docks[1].name == "Dock", "a blank name falls back")
        expect(configuration.docks[0].placement.alignment == 1, "alignment clamps into 0…1")
        expect(
            configuration.docks[0].appearance.tileSize == DockAppearance.tileSizeRange.upperBound,
            "tile size clamps to its range")
        expect(
            configuration.docks[0].appearance.magnifiedSize
                >= configuration.docks[0].appearance.tileSize,
            "magnified size never drops below the tile")
        expect(
            configuration.docks[1].appearance.magnifiedSize == 30,
            "a magnified size under the tile rises to it")
        expect(configuration.docks[0].layouts.count == 1, "a dock is never left layout-less")
        expect(
            configuration.docks[0].layouts.contains { $0.id == configuration.docks[0].activeLayoutID },
            "the active layout is one the dock has")
    }

    static func sanitizeRepairsReferences() {
        var dock = CustomDock(name: "Main", layouts: [DockLayout(name: "A"), DockLayout(name: "B")])
        dock.activeLayoutID = UUID()
        let native = NativeDockLayout(name: "Tidy", tiles: [])
        let setup = DockSetup(
            name: "Work", nativeLayoutID: UUID(),
            docks: [
                DockSetup.DockState(dockID: dock.id, isVisible: true, layoutID: UUID()),
                DockSetup.DockState(dockID: UUID(), isVisible: true, layoutID: nil),
            ])
        var configuration = DockConfiguration()
        configuration.docks = [dock]
        configuration.nativeLayouts = [native]
        configuration.setups = [setup]
        configuration.activeSetupID = UUID()
        configuration.activeNativeLayoutID = UUID()
        configuration.sanitize()
        expect(
            configuration.docks[0].activeLayoutID == configuration.docks[0].layouts[0].id,
            "a dangling active layout resets to the first")
        expect(configuration.setups[0].nativeLayoutID == nil, "a dangling native layout is cleared")
        expect(configuration.setups[0].docks.count == 1, "a state for a missing dock is dropped")
        expect(
            configuration.setups[0].docks[0].layoutID == nil,
            "a state naming a layout the dock lacks keeps whatever it shows")
        expect(configuration.activeSetupID == nil, "a dangling active setup is cleared")
        expect(configuration.activeNativeLayoutID == nil, "a dangling active native layout clears")

        configuration.activeNativeLayoutID = native.id
        configuration.activeSetupID = setup.id
        configuration.setups[0].docks[0].layoutID = configuration.docks[0].layouts[1].id
        let before = configuration
        configuration.sanitize()
        expect(configuration == before, "sanitizing a clean configuration changes nothing")
    }

    static func sanitizeDropsDuplicates() {
        let dock = CustomDock(name: "Main")
        let native = NativeDockLayout(name: "Tidy", tiles: [])
        let setup = DockSetup(name: "Work")
        var configuration = DockConfiguration()
        configuration.docks = [dock, dock]
        configuration.nativeLayouts = [native, native]
        configuration.setups = [setup, setup]
        configuration.sanitize()
        expect(configuration.docks.count == 1, "a repeated dock id is dropped")
        expect(configuration.nativeLayouts.count == 1, "a repeated native layout id is dropped")
        expect(configuration.setups.count == 1, "a repeated setup id is dropped")
    }

    static func decodingToleratesMissingKeys() {
        let empty = try? JSONDecoder().decode(DockConfiguration.self, from: Data("{}".utf8))
        expect(empty == DockConfiguration(), "an empty object decodes to the defaults")

        let id = UUID()
        let json = Data(
            #"{"activeSetupID":"\#(id.uuidString)","savesNativeDockChanges":true}"#.utf8)
        let partial = try? JSONDecoder().decode(DockConfiguration.self, from: json)
        expect(partial?.activeSetupID == id, "a present key survives a sibling being absent")
        expect(partial?.savesNativeDockChanges == true, "a present flag survives")
        expect(partial?.nativeMode == .both, "an absent mode takes its default")
        expect(partial?.docks.isEmpty == true, "an absent list decodes empty")

        let unknown = Data(#"{"nativeMode":"sideways","nativeHiding":"vanish"}"#.utf8)
        let tolerant = try? JSONDecoder().decode(DockConfiguration.self, from: unknown)
        expect(tolerant?.nativeMode == .both, "an unknown mode falls back rather than failing")
        expect(tolerant?.nativeHiding == .reachable, "an unknown hiding falls back")

        var full = DockConfiguration()
        full.docks = [CustomDock(name: "Main")]
        full.setups = [DockSetup(name: "Work")]
        full.nativeMode = .customMain
        let round = (try? JSONEncoder().encode(full)).flatMap {
            try? JSONDecoder().decode(DockConfiguration.self, from: $0)
        }
        expect(round == full, "a full configuration survives an encode/decode round-trip")

        let saved = Data(#"{"material":"frosted","tileSize":64,"magnifiedSize":80,"autoHides":true}"#.utf8)
        let appearance = try? JSONDecoder().decode(DockAppearance.self, from: saved)
        expect(appearance?.tileSize == 64, "an appearance saved before newer keys keeps its values")
        expect(appearance?.autoHides == true, "including its flags")
        expect(appearance?.showsWidgetLabels == true, "and a key it never had takes its default")
        var labelsOff = DockAppearance()
        labelsOff.showsWidgetLabels = false
        let back = (try? JSONEncoder().encode(labelsOff)).flatMap {
            try? JSONDecoder().decode(DockAppearance.self, from: $0)
        }
        expect(back?.showsWidgetLabels == false, "turning widget labels off survives a round-trip")
    }

    static func customIconsRoundTripAndOldConfigsDecode() {
        // A layout saved before custom icons existed has no key for it.
        let legacy = Data(
            #"{"bundleID":"com.apple.finder","path":"/System/Library/CoreServices/Finder.app"}"#.utf8)
        let old = try? JSONDecoder().decode(DockAppReference.self, from: legacy)
        expect(old?.customIcon == nil, "an app saved without a custom icon keeps the app's own")
        expect(old?.bundleID == "com.apple.finder", "the rest of an old reference survives")

        for icon in [
            DockCustomIcon.image(path: "/tmp/finder-flat.png"),
            .symbol(name: "folder.fill", color: .teal),
            .symbol(name: "star.fill", color: nil)
        ] {
            let reference = DockAppReference(
                bundleID: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app",
                customIcon: icon)
            let data = try? JSONEncoder().encode(DockItem(kind: .app(reference)))
            let back = data.flatMap { try? JSONDecoder().decode(DockItem.self, from: $0) }
            expect(back?.kind == .app(reference), "\(icon) survives an encode/decode round-trip")
        }

        // The icon is cosmetic: it never decides which running app a pinned item is.
        let finder = DockAppReference(bundleID: "com.apple.finder", path: "/F.app")
        var themed = finder
        themed.customIcon = .symbol(name: "star.fill", color: .red)
        expect(
            DockSlots.matches(themed, app("Finder", bundle: "com.apple.finder", path: "/F.app", pid: 1)),
            "a custom icon does not change which app a tile matches")
    }

    // MARK: - DockSlots

    static func app(_ name: String, bundle: String?, path: String? = nil, pid: Int32)
        -> DockRunningApp
    {
        DockRunningApp(
            bundleID: bundle, path: path ?? "/Applications/\(name).app", name: name,
            processID: pid, isActive: false, isHidden: false)
    }

    static func pinned(_ bundle: String, path: String) -> DockItem {
        DockItem(kind: .app(DockAppReference(bundleID: bundle, path: path)))
    }

    static func arrangeGroupsPinnedRunningAndTrailing() {
        let a = pinned("com.a", path: "/Applications/A.app")
        let spacer = DockItem(kind: .spacer(.small))
        let b = pinned("com.b", path: "/Applications/B.app")
        let slots = DockSlots.arrange(
            items: [a, spacer, b],
            running: [app("A", bundle: "com.a", pid: 1), app("C", bundle: "com.c", pid: 3)],
            minimized: [], options: DockContentOptions())
        let ids = slots.map(\.id)
        expect(
            ids == [
                "item:\(a.id.uuidString)", "item:\(spacer.id.uuidString)", "item:\(b.id.uuidString)",
                "divider:running", "running:3", "divider:trailing", "trash",
            ], "pinned, then unpinned running behind a divider, then the trailing group: \(ids)")
        if case .pinned(_, let running) = slots[0] {
            expect(running?.processID == 1, "a pinned app reports its running process")
        } else {
            expect(false, "the first slot is the pinned app")
        }
        if case .pinned(_, let running) = slots[2] {
            expect(running == nil, "a pinned app that is not running reports none")
        }
        expect(Set(ids).count == ids.count, "slot ids are unique")
    }

    static func arrangeRespectsContentOptions() {
        let window = DockMinimizedWindow(
            token: "w1", title: "Doc", appName: "A", bundleID: "com.a", appPath: "/A.app")
        let runningC = app("C", bundle: "com.c", pid: 3)
        var options = DockContentOptions()
        options.showsMinimizedWindows = true
        var slots = DockSlots.arrange(items: [], running: [runningC], minimized: [window], options: options)
        expect(
            slots.map(\.id) == ["running:3", "divider:trailing", "minimized:w1", "trash"],
            "minimized windows sit before the Trash, and nothing leads with a divider")

        options.showsRunningApps = false
        options.showsTrash = false
        slots = DockSlots.arrange(items: [], running: [runningC], minimized: [window], options: options)
        expect(slots.map(\.id) == ["minimized:w1"], "running apps and Trash can each be turned off")

        options.showsMinimizedWindows = false
        slots = DockSlots.arrange(items: [], running: [runningC], minimized: [window], options: options)
        expect(slots.isEmpty, "a dock with every automatic tile off and no items is empty")

        let pinnedApp = pinned("com.c", path: "/Applications/C.app")
        slots = DockSlots.arrange(
            items: [pinnedApp], running: [runningC], minimized: [], options: options)
        if case .pinned(_, let running) = slots.first {
            expect(running?.processID == 3, "a pinned app still shows as running with the tile off")
        } else {
            expect(false, "the pinned app is present")
        }
    }

    static func arrangeMatchesAppsByBundleThenPath() {
        let moved = DockAppReference(bundleID: "com.a", path: "/Old/A.app")
        expect(
            DockSlots.matches(moved, app("A", bundle: "com.a", path: "/New/A.app", pid: 1)),
            "a moved app still matches by bundle id")
        expect(
            !DockSlots.matches(moved, app("A", bundle: "com.other", path: "/Old/A.app", pid: 1)),
            "two different bundle ids never match, even at the same path")
        let bare = DockAppReference(bundleID: nil, path: "/Applications/A.app/")
        expect(
            DockSlots.matches(bare, app("A", bundle: nil, path: "/Applications//A.app", pid: 1)),
            "without bundle ids the standardized path decides")
        expect(
            !DockSlots.matches(bare, app("B", bundle: nil, path: "/Applications/B.app", pid: 2)),
            "different paths do not match")

        let first = pinned("com.a", path: "/A.app")
        let second = pinned("com.a", path: "/A.app")
        let slots = DockSlots.arrange(
            items: [first, second], running: [app("A", bundle: "com.a", pid: 1)], minimized: [],
            options: DockContentOptions())
        expect(!slots.contains { $0.id == "running:1" }, "a claimed app gets no second tile")
    }

    static func moveReordersBeforeDestination() {
        let items = (0..<3).map { _ in DockItem(kind: .spacer(.small)) }
        let ids = items.map(\.id)
        func order(_ moved: [DockItem]) -> [Int] { moved.compactMap { ids.firstIndex(of: $0.id) } }
        expect(order(DockSlots.move(items, from: 0, to: 2)) == [1, 0, 2], "forward move lands before")
        expect(order(DockSlots.move(items, from: 2, to: 0)) == [2, 0, 1], "backward move lands before")
        expect(order(DockSlots.move(items, from: 1, to: 3)) == [0, 2, 1], "a move to the end works")
        expect(order(DockSlots.move(items, from: 0, to: 1)) == [0, 1, 2], "moving before its own next is a no-op")
        expect(order(DockSlots.move(items, from: 1, to: 1)) == [0, 1, 2], "moving onto itself is a no-op")
        expect(order(DockSlots.move(items, from: 5, to: 0)) == [0, 1, 2], "a bad source is a no-op")
        expect(order(DockSlots.move(items, from: 0, to: 9)) == [0, 1, 2], "a bad destination is a no-op")
    }

    // MARK: - DockGeometry

    static func extentsAndLengths() {
        near(DockGeometry.thickness(tileSize: 48), 48 + 2 * 48 * 0.18, "thickness is a tile plus rim")
        near(DockGeometry.Extent.tile.length(tileSize: 48), 48, "a tile is one tile long")
        near(DockGeometry.Extent.span(2).length(tileSize: 48), 96 + 48 * 0.12, "a span adds inner gaps")
        near(DockGeometry.Extent.span(4).length(tileSize: 48), 192 + 3 * 48 * 0.12, "a wide span adds three gaps")
        near(DockGeometry.Extent.spacer(.small).length(tileSize: 48), 24, "a small spacer is half a tile")
        near(DockGeometry.Extent.spacer(.regular).length(tileSize: 48), 48, "a regular spacer is a tile")
        near(DockGeometry.Extent.divider.length(tileSize: 48), 9.6, "a divider is a fifth of a tile")
        near(DockGeometry.Extent.divider.length(tileSize: 2), 1, "a divider never vanishes")
        near(
            DockGeometry.length(of: [.tile, .tile], tileSize: 48),
            96 + 48 * 0.12 + 2 * 48 * 0.18, "two tiles add a gap and the rim")
        near(
            DockGeometry.length(of: [], tileSize: 48), 2 * 48 * 0.18,
            "an empty run is just its rim")
    }

    static func frameHugsEdgeAndClampsAlignment() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let available = CGRect(x: 0, y: 40, width: 1000, height: 730)
        func frame(_ edge: DockEdge, _ alignment: Double, length: CGFloat = 200) -> CGRect {
            DockGeometry.frame(
                length: length, thickness: 60, edge: edge, alignment: alignment, screen: screen,
                available: available)
        }
        var rect = frame(.bottom, 0.5)
        near(rect.minX, 400, "a bottom dock centres on the display")
        near(rect.minY, DockGeometry.edgeMargin, "a bottom dock sits an edge margin up")
        near(rect.width, 200, "length is kept")
        near(rect.height, 60, "thickness is kept")
        near(frame(.bottom, 0).minX, 0, "alignment 0 pins to the start")
        near(frame(.bottom, 1).maxX, 1000, "alignment 1 pins to the end")
        near(frame(.bottom, -3).minX, 0, "alignment clamps below 0")
        near(frame(.bottom, 9).maxX, 1000, "alignment clamps above 1")
        near(frame(.bottom, 0.5, length: 5000).width, 1000, "a dock longer than the edge shrinks to it")

        rect = frame(.left, 0.5)
        near(rect.minX, DockGeometry.edgeMargin, "a left dock sits an edge margin in")
        near(rect.width, 60, "a vertical dock is thickness wide")
        near(rect.height, 200, "a vertical dock is length tall")
        near(rect.midY, available.midY, "a vertical dock centres in the available height")
        near(frame(.left, 0).maxY, available.maxY, "alignment 0 pins a vertical dock to the top")
        near(frame(.left, 1).minY, available.minY, "alignment 1 pins a vertical dock to the bottom")
        rect = frame(.right, 0.5)
        near(rect.maxX, 1000 - DockGeometry.edgeMargin, "a right dock sits an edge margin in")
    }

    static func hiddenFrameAndRevealZoneFollowEdge() {
        let screen = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let shown = CGRect(x: 400, y: 56, width: 200, height: 60)
        var hidden = DockGeometry.hiddenFrame(shown: shown, edge: .bottom, screen: screen, visible: 4)
        near(hidden.maxY, screen.minY + 4, "a hidden bottom dock leaves its handle showing")
        near(hidden.minX, shown.minX, "hiding slides along one axis only")
        let left = CGRect(x: 106, y: 300, width: 60, height: 200)
        hidden = DockGeometry.hiddenFrame(shown: left, edge: .left, screen: screen, visible: 4)
        near(hidden.maxX, screen.minX + 4, "a hidden left dock leaves its handle showing")
        let right = CGRect(x: 1034, y: 300, width: 60, height: 200)
        hidden = DockGeometry.hiddenFrame(shown: right, edge: .right, screen: screen, visible: 4)
        near(hidden.minX, screen.maxX - 4, "a hidden right dock leaves its handle showing")

        var zone = DockGeometry.revealZone(shown: shown, edge: .bottom, screen: screen)
        expect(
            zone == CGRect(x: 400, y: 50, width: 200, height: 2),
            "the bottom reveal zone is a strip along the dock's width")
        zone = DockGeometry.revealZone(shown: left, edge: .left, screen: screen, depth: 3)
        expect(
            zone == CGRect(x: 100, y: 300, width: 3, height: 200),
            "the left reveal zone is a strip along the dock's length")
        zone = DockGeometry.revealZone(shown: right, edge: .right, screen: screen)
        expect(
            zone == CGRect(x: 1098, y: 300, width: 2, height: 200),
            "the right reveal zone hugs the far edge")
    }

    static func magnificationFallsOffWithDistance() {
        near(
            DockGeometry.magnification(distance: 0, tileSize: 48, magnified: 96), 96,
            "full size under the pointer")
        near(
            DockGeometry.magnification(distance: 48 * 2.5, tileSize: 48, magnified: 96), 48,
            "base size at the reach")
        near(
            DockGeometry.magnification(distance: 9999, tileSize: 48, magnified: 96), 48,
            "base size far away")
        near(
            DockGeometry.magnification(distance: -10, tileSize: 48, magnified: 96),
            DockGeometry.magnification(distance: 10, tileSize: 48, magnified: 96),
            "the lens is symmetric")
        near(
            DockGeometry.magnification(distance: 60, tileSize: 48, magnified: 96), 72,
            "half the reach is half the growth")
        expect(
            DockGeometry.magnification(distance: 20, tileSize: 48, magnified: 96)
                > DockGeometry.magnification(distance: 70, tileSize: 48, magnified: 96),
            "nearer tiles grow more")
        near(
            DockGeometry.magnification(distance: 0, tileSize: 48, magnified: 48), 48,
            "magnification off at equal sizes")
        near(
            DockGeometry.magnification(distance: 0, tileSize: 48, magnified: 30), 48,
            "a magnified size under the tile never shrinks it")
    }

    // MARK: - CustomDock

    static func layoutSteppingWraps() {
        let layouts = (1...3).map { DockLayout(name: "L\($0)") }
        var dock = CustomDock(name: "Main", layouts: layouts)
        expect(dock.layout(steppedBy: 1).id == layouts[1].id, "a step forward moves one on")
        expect(dock.layout(steppedBy: -1).id == layouts[2].id, "a step back from the first wraps")
        expect(dock.layout(steppedBy: 3).id == layouts[0].id, "a full turn lands where it started")
        expect(dock.layout(steppedBy: 7).id == layouts[1].id, "a long step wraps by the remainder")
        expect(dock.layout(steppedBy: -7).id == layouts[2].id, "a long step back wraps too")
        dock.activeLayoutID = layouts[2].id
        expect(dock.layout(steppedBy: 1).id == layouts[0].id, "a step forward from the last wraps")
        dock.activeLayoutID = UUID()
        expect(dock.layout(steppedBy: 1).id == layouts[0].id, "a stale active layout steps to the first")
        expect(dock.activeLayout.id == layouts[0].id, "a stale active layout reads as the first")
        let single = CustomDock(name: "One")
        expect(single.layout(steppedBy: 5).id == single.layouts[0].id, "one layout steps to itself")
    }

    // MARK: - DockStore

    static func freshDefaults() -> UserDefaults {
        let name = "docks-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func storeActivatesSetupAndPersists() {
        let defaults = freshDefaults()
        let store = DockStore(defaults: defaults)
        let main = store.addDock(CustomDock(name: "Main", layouts: [DockLayout(name: "A"), DockLayout(name: "B")]))
        let side = store.addDock(CustomDock(name: "Side", isVisible: true))
        let layoutB = main.layouts[1].id
        let setup = DockSetup(
            name: "Focus",
            docks: [
                DockSetup.DockState(dockID: main.id, isVisible: true, layoutID: layoutB),
                DockSetup.DockState(dockID: side.id, isVisible: false, layoutID: nil),
            ])
        store.update { $0.setups.append(setup) }
        var changes = 0
        store.onChange = { _ in changes += 1 }
        store.activateSetup(id: setup.id)
        expect(store.configuration.activeSetupID == setup.id, "the setup becomes active")
        expect(store.dock(id: main.id)?.activeLayoutID == layoutB, "the setup picks the dock's layout")
        expect(store.dock(id: side.id)?.isVisible == false, "the setup hides a dock it lists hidden")
        expect(changes == 1, "one switch is one change")
        store.activateSetup(id: setup.id)
        expect(changes == 1, "re-activating the active setup changes nothing")
        store.activateSetup(id: UUID())
        expect(changes == 1, "an unknown setup is ignored")

        let reloaded = DockStore(defaults: defaults)
        expect(reloaded.configuration == store.configuration, "the configuration persists")
        expect(reloaded.dock(id: side.id)?.isVisible == false, "a saved visibility reloads")
    }

    static func storeNamesStayUnique() {
        expect(DockStore.uniqueName("Dock", among: []) == "Dock", "a free name is kept")
        expect(DockStore.uniqueName("Dock", among: ["dock"]) == "Dock 2", "names compare ignoring case")
        expect(DockStore.uniqueName("Dock", among: ["Dock", "Dock 2"]) == "Dock 3", "the next free suffix wins")
        expect(DockStore.uniqueName("  Dock ", among: []) == "Dock", "a name is trimmed")
        let store = DockStore(defaults: freshDefaults())
        let first = store.addDock(CustomDock(name: "Dock"))
        let second = store.addDock(CustomDock(name: "Dock"))
        expect(first.name != second.name, "adding a same-named dock renames the newcomer")
        let copy = store.duplicateDock(id: first.id)
        expect(copy?.id != first.id, "a duplicate is a new dock")
        expect(copy?.isVisible == false, "a duplicate starts hidden")
        expect(
            copy.map { Set($0.layouts.map(\.id)).isDisjoint(with: first.layouts.map(\.id)) } == true,
            "a duplicate shares no layout identity with the original")
    }
}
