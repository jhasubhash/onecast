#if DEBUG
import AppKit

/// Answers the agent channel's commands through the same coordinators a key or a click reaches.
@MainActor
final class AgentControlCoordinator {
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
    }

    /// What an action answers: the palette after it, and how long its `until` took to hold.
    private struct Outcome: Encodable {
        let palette: AgentSnapshot.Palette
        var waited: Double?
        var detail: String?
    }

    private struct Entry: Encodable {
        let id: String
        let name: String
        let kind: String
        let subtitle: String?
    }

    private struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// How often `until` is re-read; quick enough for a typing loop, cheap on the main actor.
    private static let pollInterval: Duration = .milliseconds(40)
    /// Unredacted: a condition is matched here and its trees are never sent back.
    private static let conditionOptions = AgentAccessibilityReader.Options(includeContent: true)

    func handle(_ request: AgentRequest) async -> Data {
        do {
            var detail: String?
            switch request.command {
            case .ping:
                return AgentReply.success(build)
            case .state(let includeContent, let includeElements, let pruned):
                return AgentReply.success(
                    snapshot(
                        includeContent: includeContent, trees: includeElements ? nil : [],
                        pruned: pruned))
            case .entries(let query, let kind, let limit):
                return AgentReply.success(entries(query: query, kind: kind, limit: limit))
            case .logs(let query):
                return AgentReply.success(try await AgentLogReader.entries(query))
            case .extensionState:
                return AgentReply.success(json: core.extensions.diagnostics)
            case .plugins:
                return AgentReply.success(json: core.plugins.diagnostics)
            case .capture(let id, let path):
                guard let window = AgentWindowInspector.window(id: id) else {
                    throw Failure("No visible window \"\(id)\".")
                }
                var capture = try await AgentWindowCapture.capture(window, id: id, to: path)
                if id == "palette" { capture.rows = snapshot(trees: ["palette"]).palette.rows }
                return AgentReply.success(capture)
            default:
                detail = try await perform(request.command)
            }
            await AgentKeyboard.drained()
            var outcome = Outcome(palette: paletteSnapshot, detail: detail)
            if let until = request.until {
                outcome.waited = try await wait(for: until, timeout: request.timeout)
                outcome = Outcome(palette: paletteSnapshot, waited: outcome.waited, detail: detail)
            }
            return AgentReply.success(outcome)
        } catch let failure as Failure {
            return AgentReply.failure(failure.message)
        } catch {
            return AgentReply.failure(error.localizedDescription)
        }
    }

    private func perform(_ command: AgentCommand) async throws -> String? {
        switch command {
        case .ping, .state, .entries, .waitFor, .logs, .capture, .extensionState, .plugins:
            return nil
        case .show(let name, let query):
            guard let mode = PaletteMode(rawValue: name) else {
                throw Failure(
                    "Unknown mode \"\(name)\"; one of "
                        + PaletteMode.allCases.map(\.rawValue).joined(separator: ", ") + ".")
            }
            core.paletteCoordinator.showPalette(mode: mode, restoreAnyMode: true, seeding: query)
        case .hide:
            core.paletteCoordinator.hidePalette()
        case .setQuery(let text):
            core.palette.query = text
        case .key(let chords, let count, let windowID):
            let keys = try chords.map(KeyChord.parse)
            let window = try target(windowID)
            for _ in 0..<count {
                for key in keys { await AgentKeyboard.press(key, in: window) }
            }
        case .type(let text, let windowID):
            let window = try target(windowID)
            for character in text {
                guard let key = KeyChord.typing(character) else { continue }
                await AgentKeyboard.press(key, in: window)
            }
        case .select(let index):
            core.palette.selection = index
        case .activate(let index):
            if let index { core.palette.selection = index }
            await AgentKeyboard.press(try KeyChord.parse("return"), in: try target(nil))
        case .popToRoot:
            core.paletteCoordinator.popToRootNow()
        case .closeScreen:
            core.paletteCoordinator.closeScreen()
        case .openSettings(let name):
            core.settingsCoordinator.showSettings(tab: try settingsTab(named: name))
        case .openURL(let text):
            guard let url = URL(string: text) else { throw Failure("Not a URL: \(text)") }
            core.handleOpenURL(url)
        case .runEntry(let id):
            guard let entry = core.appIndex.apps.first(where: { $0.id == id }) else {
                throw Failure("No entry \"\(id)\"; list them with the entries action.")
            }
            core.launcherCoordinator.launch(entry)
        case .setAppearance(let name):
            guard let appearance = AppAppearance(rawValue: name) else {
                throw Failure("Appearance is system, light or dark.")
            }
            core.settings.appearance = appearance
        case .press(let match, let windowID):
            let key = try windowID.map { try AgentWindowInspector.key(of: target($0)) }
            switch AgentAccessibilityReader.press(match, in: key) {
            case .pressed(let role): return role
            case .notFound: throw Failure("Nothing named \"\(match)\" to press.")
            case .refused: throw Failure("\"\(match)\" did not accept a press.")
            }
        }
        return nil
    }

    /// Polls rather than observing: the condition spans windows and AX trees no tracker covers.
    private func wait(for condition: AgentCondition, timeout: Double) async throws -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start + .milliseconds(Int(timeout * 1000))
        let scope = condition.treeScope
        while true {
            let windows = AgentWindowInspector.windows(trees: scope, options: Self.conditionOptions)
            let palette = self.palette(reading: windows, scope: scope)
            if condition.isMet(palette: palette, windows: windows) {
                let elapsed = clock.now - start
                return Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
            }
            guard clock.now < deadline else {
                throw Failure(
                    "Timed out after \(timeout)s waiting for \(condition.summary); palette is "
                        + "\(palette.visible ? "visible" : "hidden"), mode \(palette.mode), "
                        + "query \"\(palette.query)\", selection \(palette.selection), windows "
                        + windows.map(\.id).joined(separator: ", ") + ".")
            }
            try await Task.sleep(for: Self.pollInterval)
        }
    }

    /// The named window, else the key window: where a posted key event will be dispatched.
    private func target(_ id: String?) throws -> NSWindow {
        if let id {
            guard let window = AgentWindowInspector.window(id: id) else {
                throw Failure("No visible window \"\(id)\".")
            }
            return window
        }
        guard let window = NSApp.keyWindow else {
            throw Failure("No key window; show the palette first or pass \"window\".")
        }
        return window
    }

    private func settingsTab(named name: String?) throws -> SettingsTab? {
        guard let name else { return nil }
        let match = SettingsTab.allCases.first {
            String(describing: $0).caseInsensitiveCompare(name) == .orderedSame
                || $0.title.caseInsensitiveCompare(name) == .orderedSame
        }
        guard let match else {
            throw Failure(
                "Unknown Settings tab \"\(name)\"; one of "
                    + SettingsTab.allCases.map { String(describing: $0) }.joined(separator: ", ")
                    + ".")
        }
        return match
    }

    private func entries(query: String?, kind: String?, limit: Int) -> [Entry] {
        core.appIndex.apps
            .filter { entry in
                (kind.map { entry.kind.rawValue.caseInsensitiveCompare($0) == .orderedSame } ?? true)
                    && (query.map { entry.name.localizedCaseInsensitiveContains($0) } ?? true)
            }
            .prefix(max(1, limit))
            .map { Entry(id: $0.id, name: $0.name, kind: $0.kind.rawValue, subtitle: $0.subtitle) }
    }

    /// `trees` names the windows whose AX tree is read; nil reads every window's.
    func snapshot(
        includeContent: Bool = false, trees scope: Set<String>? = nil, pruned: Bool = true
    ) -> AgentSnapshot {
        let options = AgentAccessibilityReader.Options(
            includeContent: includeContent,
            redactsPaletteText: !includeContent && core.palette.mode == .clipboard,
            pruned: pruned)
        let windows = AgentWindowInspector.windows(trees: scope, options: options)
        return AgentSnapshot(
            build: build, palette: palette(reading: windows, scope: scope), windows: windows,
            focus: focus)
    }

    /// The palette, with its rows and bar pills when its tree was among those read.
    private func palette(
        reading windows: [AgentSnapshot.Window], scope: Set<String>?
    ) -> AgentSnapshot.Palette {
        var palette = paletteSnapshot
        guard palette.visible, scope?.contains("palette") ?? true else { return palette }
        let elements = windows.first { $0.id == "palette" }?.elements ?? []
        palette.rows = AgentElement.rows(in: elements)
        palette.barControls = AgentElement.barControls(in: elements)
        return palette
    }

    private var build: AgentSnapshot.Build {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = info["CFBundleVersion"] as? String ?? "?"
        return AgentSnapshot.Build(
            bundleID: Bundle.main.bundleIdentifier ?? "?", version: "\(version) (\(buildNumber))",
            pid: ProcessInfo.processInfo.processIdentifier,
            accessibilityTrusted: Permissions.isAccessibilityTrusted())
    }

    private var paletteSnapshot: AgentSnapshot.Palette {
        let palette = core.palette
        let panel = NSApp.windows.first { $0 is PalettePanel }
        return AgentSnapshot.Palette(
            visible: core.paletteCoordinator.isVisible,
            mode: palette.mode.rawValue,
            query: palette.query,
            selection: palette.selection,
            backStack: palette.backStack.map {
                AgentSnapshot.Frame(mode: $0.mode.rawValue, query: $0.query, selection: $0.selection)
            },
            aiBar: palette.aiBar,
            collapsed: core.paletteCoordinator.paletteIsCollapsed,
            editingField: palette.isEditingField,
            controlListOpen: palette.isControlListOpen,
            frame: panel.flatMap { $0.isVisible ? AgentWindowInspector.rect($0.frame) : nil },
            rows: nil)
    }

    private var focus: AgentSnapshot.Focus {
        let key = NSApp.keyWindow
        return AgentSnapshot.Focus(
            keyWindow: key.flatMap { key in
                AgentWindowInspector.identified().first { $0.window === key }?.id
            },
            firstResponder: key?.firstResponder.map { String(describing: type(of: $0)) },
            frontmostApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
#endif
