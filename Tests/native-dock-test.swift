import Foundation

@main
@MainActor
struct NativeDockTests {
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
        appTileReadsItsFields()
        trailingSlashAndEscapesDecodeToAPath()
        posixPathTileReadsAsAPath()
        spacerKindsAreTold()
        unknownTileKeepsEveryKey()
        everyKeyOfAnAppTileSurvivesTheRoundTrip()
        missingFieldsDegradeInsteadOfFailing()
        preferenceValueShapes()
        synthesizedAppReadsBackAsTheSameApp()
        synthesizedSpacersReadBackAsTheSameSize()
        editedSpacerSizeBeatsStaleRaw()
        corruptRawFallsBackToSynthesis()
        otherTileWithoutRawCannotBeWritten()
        resolveKeepsOrderAndUnknownTilesVerbatim()
        resolveListsMissingAppsOnce()
        resolveRepointsAMovedApp()
        resolveFindsAnAppByBundleIDWhenItsPathIsBlank()
        signatureIgnoresChurnButSeesRealChanges()
        hidingFromPristineWritesOnlyAutohide()
        suppressedAlsoPushesTheDelayOut()
        reapplyingNeverOverwritesSavedOriginals()
        alreadyAutohidingNeedsNoRestart()
        reachableToSuppressedIsOneDirectStep()
        suppressedBackToReachableRestoresTheUsersDelay()
        restoreRemovesKeysThatWereAbsent()
        restoreTouchesOnlyWhatDiffers()
        restoreWithoutSentinelDoesNothing()
        userUndoingAutohideWhileHiddenIsHiddenAgain()
        settingsEncodeWithoutAbsentKeys()
        errorMessagesNameTheApps()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Fixtures

    static func safari() -> [String: Any] {
        [
            "GUID": 4_242_424_242,
            "tile-type": "file-tile",
            "tile-data": [
                "bundle-identifier": "com.apple.Safari",
                "dock-extra": false,
                "file-data": [
                    "_CFURLString": "file:///Applications/Safari.app/",
                    "_CFURLStringType": 15
                ] as [String: Any],
                "file-label": "Safari",
                "file-mod-date": 3_700_000_000.5,
                "file-type": 41,
                "parent-mod-date": Date(timeIntervalSinceReferenceDate: 800_000_000),
                "book": Data([0x62, 0x6F, 0x6F, 0x6B])
            ] as [String: Any]
        ]
    }

    static func recents() -> [String: Any] {
        [
            "GUID": 77,
            "tile-type": "recents-tile",
            "tile-data": ["list-type": 1, "show-as": 3] as [String: Any]
        ]
    }

    static func spacer(_ type: String) -> [String: Any] {
        ["tile-type": type, "tile-data": [String: Any]()]
    }

    static func equal(_ left: [String: Any]?, _ right: [String: Any]) -> Bool {
        guard let left else { return false }
        return NSDictionary(dictionary: left).isEqual(to: right)
    }

    static func decode(_ raw: Data?) -> [String: Any]? {
        guard let raw else { return nil }
        return try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil)
            as? [String: Any]
    }

    static func found(_ bundleID: String?, _ path: String) -> String? { path }

    // MARK: - Reading tiles

    static func appTileReadsItsFields() {
        let tile = NativeDockPlist.tile(from: safari())
        expect(
            tile.kind
                == .app(
                    bundleID: "com.apple.Safari", path: "/Applications/Safari.app", label: "Safari"),
            "a file tile becomes an app with its bundle ID, path and label")
        expect(tile.raw != nil, "an app tile keeps its dictionary")
    }

    static func trailingSlashAndEscapesDecodeToAPath() {
        var dictionary = safari()
        dictionary["tile-data"] =
            [
                "bundle-identifier": "com.microsoft.VSCode",
                "file-label": "Visual Studio Code",
                "file-data": [
                    "_CFURLString": "file:///Applications/Visual%20Studio%20Code.app/",
                    "_CFURLStringType": 15
                ] as [String: Any]
            ] as [String: Any]
        guard case .app(_, let path, _) = NativeDockPlist.tile(from: dictionary).kind else {
            return expect(false, "an escaped file URL still reads as an app")
        }
        expect(path == "/Applications/Visual Studio Code.app", "percent escapes decode, got \(path)")
    }

    static func posixPathTileReadsAsAPath() {
        var dictionary = safari()
        dictionary["tile-data"] =
            [
                "file-label": "Notes",
                "file-data": ["_CFURLString": "/System/Applications/Notes.app/", "_CFURLStringType": 0]
                    as [String: Any]
            ] as [String: Any]
        let tile = NativeDockPlist.tile(from: dictionary)
        expect(
            tile.kind == .app(bundleID: nil, path: "/System/Applications/Notes.app", label: "Notes"),
            "a type-0 POSIX path reads as a path, without a trailing slash")
    }

    static func spacerKindsAreTold() {
        expect(
            NativeDockPlist.tile(from: spacer("spacer-tile")).kind == .spacer(.regular),
            "spacer-tile is a regular spacer")
        expect(
            NativeDockPlist.tile(from: spacer("small-spacer-tile")).kind == .spacer(.small),
            "small-spacer-tile is a small spacer")
    }

    static func unknownTileKeepsEveryKey() {
        let tile = NativeDockPlist.tile(from: recents())
        expect(tile.kind == .other(type: "recents-tile"), "an unrecognised type stays opaque")
        expect(equal(decode(tile.raw), recents()), "its raw bytes decode to the original dictionary")
        expect(
            equal(NativeDockPlist.dictionary(for: tile), recents()),
            "writing it back yields the original dictionary")
        let resolution = NativeDockPlist.resolve([tile], locate: found)
        expect(
            resolution.dictionaries.count == 1 && equal(resolution.dictionaries[0], recents()),
            "resolving passes it through unchanged")
    }

    static func everyKeyOfAnAppTileSurvivesTheRoundTrip() {
        let tile = NativeDockPlist.tile(from: safari())
        let written = NativeDockPlist.dictionary(for: tile)
        expect(equal(written, safari()), "GUID, dates, data and flags all come back")
        let again = written.map(NativeDockPlist.tile(from:))
        expect(again?.kind == tile.kind, "re-reading the written dictionary gives the same kind")
        expect(
            equal(decode(again?.raw), safari()),
            "and the same stored dictionary after a second pass")
    }

    static func missingFieldsDegradeInsteadOfFailing() {
        let bundleOnly: [String: Any] = [
            "tile-type": "file-tile", "tile-data": ["bundle-identifier": "com.acme.App"]
        ]
        expect(
            NativeDockPlist.tile(from: bundleOnly).kind
                == .app(bundleID: "com.acme.App", path: "", label: "com.acme.App"),
            "a file tile with only a bundle ID is an app labelled by it")

        let pathOnly: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": ["file-data": ["_CFURLString": "file:///Applications/Acme%20Pro.app/"]]
        ]
        expect(
            NativeDockPlist.tile(from: pathOnly).kind
                == .app(bundleID: nil, path: "/Applications/Acme Pro.app", label: "Acme Pro"),
            "a missing label falls back to the app's file name")

        let nameless: [String: Any] = ["tile-type": "file-tile", "tile-data": ["file-label": "X"]]
        expect(
            NativeDockPlist.tile(from: nameless).kind == .other(type: "file-tile"),
            "a file tile naming nothing to launch stays opaque")

        expect(
            NativeDockPlist.tile(from: [:]).kind == .other(type: "unknown"),
            "a tile with no type stays opaque")

        let oddData: [String: Any] = ["tile-type": "spacer-tile", "tile-data": "oops"]
        expect(
            NativeDockPlist.tile(from: oddData).kind == .spacer(.regular),
            "a spacer ignores a malformed tile-data")
    }

    static func preferenceValueShapes() {
        expect(NativeDockPlist.tiles(fromPreference: nil)?.isEmpty == true, "an absent key is an empty Dock")
        expect(NativeDockPlist.tiles(fromPreference: "nope") == nil, "a non-array is unreadable")
        expect(
            NativeDockPlist.tiles(fromPreference: ["a", "b"]) == nil, "an array of non-tiles is unreadable")
        let tiles = NativeDockPlist.tiles(fromPreference: [safari(), spacer("spacer-tile")])
        expect(tiles?.count == 2, "an array of dictionaries reads one tile each")
    }

    // MARK: - Writing tiles

    static func synthesizedAppReadsBackAsTheSameApp() {
        let kind = NativeDockTile.Kind.app(
            bundleID: "com.apple.Safari", path: "/Applications/Safari.app", label: "Safari")
        let dictionary = NativeDockPlist.dictionary(for: NativeDockTile(kind: kind, raw: nil))
        let fileData = (dictionary?["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
        expect(dictionary?["tile-type"] as? String == "file-tile", "an authored app is a file tile")
        expect(
            fileData?["_CFURLString"] as? String == "file:///Applications/Safari.app/",
            "its location is a directory file URL")
        expect(fileData?["_CFURLStringType"] as? Int == 15, "the URL type marks a file URL")
        expect(
            dictionary.map { NativeDockPlist.tile(from: $0).kind } == kind,
            "reading the synthesized dictionary yields the app that made it")
    }

    static func synthesizedSpacersReadBackAsTheSameSize() {
        for size in DockSpacerSize.allCases {
            let dictionary = NativeDockPlist.dictionary(
                for: NativeDockTile(kind: .spacer(size), raw: nil))
            expect(
                dictionary.map { NativeDockPlist.tile(from: $0).kind } == .spacer(size),
                "a \(size.rawValue) spacer round-trips")
        }
    }

    static func editedSpacerSizeBeatsStaleRaw() {
        let stored = NativeDockPlist.tile(from: spacer("small-spacer-tile"))
        let edited = NativeDockTile(kind: .spacer(.regular), raw: stored.raw)
        expect(
            NativeDockPlist.dictionary(for: edited)?["tile-type"] as? String == "spacer-tile",
            "a spacer resized in Onecast is written at the new size")
    }

    static func corruptRawFallsBackToSynthesis() {
        let kind = NativeDockTile.Kind.app(bundleID: nil, path: "/Applications/Acme.app", label: "Acme")
        let tile = NativeDockTile(kind: kind, raw: Data([0, 1, 2, 3]))
        expect(
            NativeDockPlist.dictionary(for: tile)?["tile-type"] as? String == "file-tile",
            "an app whose stored bytes are unreadable is rebuilt from its fields")
    }

    static func otherTileWithoutRawCannotBeWritten() {
        let tile = NativeDockTile(kind: .other(type: "recents-tile"), raw: nil)
        expect(
            NativeDockPlist.dictionary(for: tile) == nil, "an opaque tile with no bytes has nothing to write")
        let resolution = NativeDockPlist.resolve([tile], locate: found)
        expect(resolution.unwritable == ["recents-tile"], "resolve reports its type")
        expect(resolution.dictionaries.isEmpty, "and writes nothing for it")
    }

    // MARK: - Resolving

    static func resolveKeepsOrderAndUnknownTilesVerbatim() {
        let tiles = [
            NativeDockPlist.tile(from: safari()),
            NativeDockPlist.tile(from: spacer("small-spacer-tile")),
            NativeDockPlist.tile(from: recents())
        ]
        let resolution = NativeDockPlist.resolve(tiles, locate: found)
        expect(resolution.dictionaries.count == 3, "every tile is written")
        expect(
            equal(resolution.dictionaries[0], safari()), "an app is written verbatim when it is where it was")
        expect(
            resolution.dictionaries[1]["tile-type"] as? String == "small-spacer-tile",
            "order is preserved")
        expect(equal(resolution.dictionaries[2], recents()), "the unknown tile is verbatim")
        expect(resolution.missingApps.isEmpty && resolution.unwritable.isEmpty, "nothing is flagged")
    }

    static func resolveListsMissingAppsOnce() {
        let ghost = NativeDockTile(
            kind: .app(bundleID: "com.gone.Ghost", path: "/Applications/Ghost.app", label: "Ghost"),
            raw: nil)
        let unlabelled = NativeDockTile(
            kind: .app(bundleID: "com.gone.Other", path: "", label: ""), raw: nil)
        let resolution = NativeDockPlist.resolve(
            [ghost, NativeDockPlist.tile(from: safari()), ghost, unlabelled],
            locate: { bundleID, path in bundleID == "com.apple.Safari" ? path : nil })
        expect(
            resolution.missingApps == ["Ghost", "com.gone.Other"],
            "missing apps are named once, by label else bundle ID, got \(resolution.missingApps)")
        expect(resolution.dictionaries.count == 1, "only the installed app is kept")
    }

    static func resolveRepointsAMovedApp() {
        let tile = NativeDockPlist.tile(from: safari())
        let resolution = NativeDockPlist.resolve(
            [tile], locate: { _, _ in "/Applications/Utilities/Safari.app" })
        let data = resolution.dictionaries.first?["tile-data"] as? [String: Any]
        let fileData = data?["file-data"] as? [String: Any]
        expect(
            fileData?["_CFURLString"] as? String == "file:///Applications/Utilities/Safari.app/",
            "the tile points at where the bundle ID resolved")
        expect(data?["file-label"] as? String == "Safari", "the rest of the tile is kept")
        expect(resolution.dictionaries.first?["GUID"] as? Int == 4_242_424_242, "even its GUID")
        expect(resolution.missingApps.isEmpty, "a relocated app is not missing")
    }

    static func resolveFindsAnAppByBundleIDWhenItsPathIsBlank() {
        let tile = NativeDockTile(
            kind: .app(bundleID: "com.acme.App", path: "", label: "Acme"), raw: nil)
        let resolution = NativeDockPlist.resolve(
            [tile], locate: { bundleID, _ in bundleID == "com.acme.App" ? "/Applications/Acme.app" : nil })
        let fileData =
            (resolution.dictionaries.first?["tile-data"] as? [String: Any])?["file-data"]
            as? [String: Any]
        expect(
            fileData?["_CFURLString"] as? String == "file:///Applications/Acme.app/",
            "a tile with no saved path is given the one its bundle ID resolves to")
    }

    static func signatureIgnoresChurnButSeesRealChanges() {
        let original = [
            NativeDockPlist.tile(from: safari()), NativeDockPlist.tile(from: spacer("spacer-tile"))
        ]
        var churned = safari()
        churned["GUID"] = 1
        var churnedData = churned["tile-data"] as? [String: Any] ?? [:]
        churnedData["file-mod-date"] = 1.0
        churnedData["file-label"] = "Safari Renamed"
        churned["tile-data"] = churnedData
        let rewritten = [
            NativeDockPlist.tile(from: churned), NativeDockPlist.tile(from: spacer("spacer-tile"))
        ]
        expect(
            NativeDockPlist.signature(of: original) == NativeDockPlist.signature(of: rewritten),
            "GUIDs, dates and labels do not change what the Dock shows")
        expect(
            NativeDockPlist.signature(of: original) != NativeDockPlist.signature(of: original.reversed()),
            "order matters")
        let small = [original[0], NativeDockPlist.tile(from: spacer("small-spacer-tile"))]
        expect(
            NativeDockPlist.signature(of: original) != NativeDockPlist.signature(of: small),
            "a spacer's size matters")
        expect(
            NativeDockPlist.signature(of: original) != NativeDockPlist.signature(of: [original[0]]),
            "a removed tile matters")
    }

    // MARK: - Hiding plan

    typealias Plan = NativeDockHidingPlan
    typealias Settings = NativeDockHidingPlan.Settings

    static func hidingFromPristineWritesOnlyAutohide() {
        let step = Plan.step(hidden: true, hiding: .reachable, current: Settings(), saved: nil)
        expect(step.originals == Settings(), "an untouched Dock is remembered as all-absent")
        expect(step.edits.autohide == .set(true), "autohide is switched on")
        expect(step.edits.autohideDelay == nil, "reachable leaves the delay alone")
        expect(step.edits.autohideTimeModifier == nil, "and the animation time")
        expect(step.restartsDock, "a change restarts the Dock")
    }

    static func suppressedAlsoPushesTheDelayOut() {
        let step = Plan.step(hidden: true, hiding: .suppressed, current: Settings(), saved: nil)
        expect(step.edits.autohide == .set(true), "autohide is switched on")
        expect(step.edits.autohideDelay == .set(Plan.suppressedDelay), "the reveal delay is huge")
        expect(Plan.suppressedDelay >= 1000, "the delay is at least a thousand seconds")
    }

    static func reapplyingNeverOverwritesSavedOriginals() {
        let originals = Settings(autohide: false, autohideDelay: 0.2, autohideTimeModifier: 0.4)
        let hiddenState = Plan.hiddenSettings(.suppressed, originals: originals)
        let step = Plan.step(hidden: true, hiding: .suppressed, current: hiddenState, saved: originals)
        expect(step.originals == originals, "the hidden state is never mistaken for the user's own")
        expect(step.edits.isEmpty && !step.restartsDock, "an already-hidden Dock is not touched")
    }

    static func alreadyAutohidingNeedsNoRestart() {
        let mine = Settings(autohide: true, autohideDelay: 0.1)
        let step = Plan.step(hidden: true, hiding: .reachable, current: mine, saved: nil)
        expect(step.originals == mine, "the user's values are still recorded")
        expect(step.edits.isEmpty && !step.restartsDock, "nothing to write means no restart")
    }

    static func reachableToSuppressedIsOneDirectStep() {
        let originals = Settings(autohide: false, autohideDelay: 0.2)
        let reachable = Plan.hiddenSettings(.reachable, originals: originals)
        let step = Plan.step(hidden: true, hiding: .suppressed, current: reachable, saved: originals)
        expect(step.originals == originals, "the originals survive the mode change")
        expect(step.edits.autohide == nil, "autohide is already on")
        expect(step.edits.autohideDelay == .set(Plan.suppressedDelay), "only the delay moves")
        expect(step.restartsDock, "and it takes a restart")
    }

    static func suppressedBackToReachableRestoresTheUsersDelay() {
        let withDelay = Settings(autohide: false, autohideDelay: 0.2)
        let suppressed = Plan.hiddenSettings(.suppressed, originals: withDelay)
        let kept = Plan.step(hidden: true, hiding: .reachable, current: suppressed, saved: withDelay)
        expect(kept.edits.autohideDelay == .set(0.2), "the user's own delay comes back")

        let noDelay = Settings(autohide: false)
        let bare = Plan.hiddenSettings(.suppressed, originals: noDelay)
        let removed = Plan.step(hidden: true, hiding: .reachable, current: bare, saved: noDelay)
        expect(removed.edits.autohideDelay == .remove, "an unset delay is removed, not zeroed")
    }

    static func restoreRemovesKeysThatWereAbsent() {
        let current = Plan.hiddenSettings(.suppressed, originals: Settings())
        let step = Plan.step(hidden: false, hiding: .reachable, current: current, saved: Settings())
        expect(step.edits.autohide == .remove, "autohide was never set, so it is removed")
        expect(step.edits.autohideDelay == .remove, "the delay was never set, so it is removed")
        expect(step.edits.autohideTimeModifier == nil, "an untouched key is left alone")
        expect(step.originals == nil, "the sentinel is released")
        expect(step.restartsDock, "the Dock restarts to pick it up")
    }

    static func restoreTouchesOnlyWhatDiffers() {
        let originals = Settings(autohide: true, autohideDelay: 0.2, autohideTimeModifier: 0.4)
        let current = Plan.hiddenSettings(.suppressed, originals: originals)
        let step = Plan.step(hidden: false, hiding: .reachable, current: current, saved: originals)
        expect(step.edits.autohide == nil, "autohide was on already and stays on")
        expect(step.edits.autohideDelay == .set(0.2), "the delay goes back")
        expect(step.edits.autohideTimeModifier == nil, "the animation time never moved")
        expect(step.originals == nil, "the sentinel is released")
    }

    static func restoreWithoutSentinelDoesNothing() {
        let step = Plan.step(
            hidden: false, hiding: .reachable, current: Settings(autohide: true, autohideDelay: 5),
            saved: nil)
        expect(step.edits.isEmpty && !step.restartsDock, "settings Onecast never changed are left alone")
        expect(step.originals == nil, "and nothing is held")
    }

    static func userUndoingAutohideWhileHiddenIsHiddenAgain() {
        let originals = Settings(autohide: false)
        let step = Plan.step(hidden: true, hiding: .reachable, current: originals, saved: originals)
        expect(step.edits.autohide == .set(true), "the Dock is hidden again")
        expect(step.originals == originals, "from the same originals")
    }

    static func settingsEncodeWithoutAbsentKeys() {
        guard
            let data = try? JSONEncoder().encode(Settings(autohide: nil, autohideDelay: 0.5)),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return expect(false, "settings encode as JSON") }
        expect(Set(object.keys) == ["autohideDelay"], "an absent key is absent in the sentinel")
        expect(
            (try? JSONDecoder().decode(Settings.self, from: data)) == Settings(autohideDelay: 0.5),
            "and decodes back as absent")
    }

    // MARK: - Errors

    static func errorMessagesNameTheApps() {
        let one = NativeDockError.missingApps(["Ghost"]).errorDescription ?? ""
        expect(one.contains("Ghost") && one.contains("it"), "one missing app is named")
        let many = NativeDockError.missingApps(["A", "B", "C", "D", "E", "F", "G"]).errorDescription ?? ""
        expect(many.contains("A, B, C, D, E and 2 more"), "a long list is capped, got \(many)")
        expect(
            NativeDockError.unwritableTiles(["recents-tile"]).errorDescription?.contains("recents-tile")
                == true,
            "an unwritable tile names its type")
        expect(NativeDockError.writeFailed.errorDescription?.isEmpty == false, "every case has a message")
        expect(
            NativeDockError.unreadableLayout.errorDescription?.isEmpty == false, "every case has a message")
    }
}
