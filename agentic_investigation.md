# Agentic investigation: making Onecast drivable and debuggable by an agent

Date: 2026-10-08. Scope: what Onecast needs so a coding agent (Claude Code or similar) can drive its UI,
read its state and debug problems quickly, without relying on screenshots and synthesized keystrokes
alone.

> **Status (2026-10-08): implemented, phases 0–7.** How it works and how to use it:
> [custom_docs/AGENT_CONTROL.md](custom_docs/AGENT_CONTROL.md). Where the build departed from
> this plan, and why:
>
> - **Transport**: loopback TCP speaking plain HTTP/1.1 with a per-launch bearer token, not a Unix
>   socket, so `curl` and a dependency-free Node MCP shim both work as clients.
> - **Element trees** come from the AX API on the app's own pid, **on the main thread**. In-process
>   `accessibilityChildren()` returns only the hosting view, because SwiftUI serves its tree through
>   the AX API alone. AppKit answers its own pid inline on the calling thread, so an off-main read
>   trapped in Auto Layout. It needs Onecast Dev's Accessibility grant.
> - **Rows** (§4.1): no per-screen `agentRows`. `selectionFrame(_:)`, which every selectable list
>   already uses, now makes each row an AX element with `isSelected`, and `state` reads rows from
>   the tree. That covers ~15 screens in one place and gives VoiceOver real rows.
> - **Logs** (§4.5): no wrapper or ring buffer. `OSLogStore(scope: .currentProcessIdentifier)` reads
>   the process's own `Logger` entries and in-process framework faults.
> - **Not built**: the `ONECAST_DATA_ROOT` seam and fixture seeding (§4.8). Both are flags, against
>   the "no flags" posture, and `state`'s redaction covers the privacy concern.
>   `includeContent` is the opt-in.
> - Found along the way: SwiftUI exposed no palette rows to VoiceOver, and the launcher's selection
>   can intermittently reset to 0 when the open-time app-index refresh lands after a ↓.

## TL;DR

Today an agent controls Onecast the same way a person does, but blind. It types global key codes
through `osascript`, waits on fixed `sleep`s, takes screenshots, and adds temporary `FileHandle` logging
when the pixels disagree with what it expected. Every step costs seconds, depends on which app has
focus, and gives back pixels instead of facts.

The fix is a **Debug-only control channel inside the app**: a small local server owned by `AppCore` that
answers "what is on screen, what is selected, what went wrong" as JSON, and accepts "open this mode,
type this, press this key, run this entry, capture this panel". The app already contains almost every
piece it needs:

- `AIToolBridge` + `AIToolHelper` is a working pattern for a token-gated loopback listener with a stdio
  MCP server in front of it.
- `PaletteCoordinator`/`PaletteState` already hold mode, query, selection and back stack as observable
  state.
- `handleOpenURL` already routes `onecast://` links.

If that channel is exposed as an **MCP server**, Claude Code can call `onecast.state()` or
`onecast.press("down")` as tools, each in milliseconds.

Recommended order of work (details in §5):

1. A **semantic state snapshot** (mode, query, rows, selection, footer, open windows, last errors). This
   is the biggest single win.
2. **In-process actions** (show mode, set query, send a key to the panel, activate a row, open a
   Settings tab), plus **wait-for-condition** in place of `sleep`.
3. **Per-window capture** from inside the app: exactly the panel, no coordinate maths.
4. **Structured logging** (`Logger` per feature plus an in-memory ring buffer the channel can return) in
   place of ad-hoc `/tmp` logs.
5. **Accessibility identifiers and window titles**, so AX- and ComputerUse-based fallbacks stop being
   guesswork.
6. Scripts and a Claude Code skill that wrap build → sign check → relaunch → drive.

---

## 1. How an agent drives Onecast today

Sources: `custom_docs/UI_TESTS.md` §2–§5, `docs/testing.md`, and the code surveyed below.

| Step | Mechanism today | Cost / failure mode |
| --- | --- | --- |
| Rebuild + relaunch | `xcodebuild …`, `pkill`, `open`, `sleep 6` | ~6 s idle on every run; a stale dylib if you forget |
| Open the palette | `osascript … key code 49 using {command down}` | needs the user's hotkey bound; needs Accessibility for `osascript`'s host; keys land in the *previous* app if sent within ~2 s |
| Type / navigate | `System Events keystroke` / `key code`, one `osascript` process per key | ~100–300 ms per spawn plus a mandatory `sleep`; focus races |
| Know when the UI is ready | fixed `sleep 1.5`…`sleep 3` | flaky on network-backed lists ("↓ resets selection") |
| See the result | `System Events get {position,size} of windows` → `screencapture -R` → the model reads the PNG | windows have **empty titles** (verified: `get name of windows` returns blanks), so you have to guess which one is the palette; reading pixels is error-prone (UI_TESTS §4 records a misread highlight) |
| Find out *why* | hand-written `debugLog` to `/tmp/tcdebug.log`, rebuild, rerun, strip afterwards | a full rebuild cycle per hypothesis; the lines have to be removed again |
| Read logs | barely possible | only **5** `Logger` call sites in ~148k lines of Swift; **618** `try?` sites that drop errors silently |
| Change settings | `defaults write com.onecast.app.dev …`, or `settings.json` once it is enabled | works for preferences; capability grants are deliberately excluded (correct) |

What already exists and helps:

- **URL scheme**: `onecast://`, `raycast://` and `com.raycast://` go to `AppCore.handleOpenURL`
  (`Onecast/App/AppCore.swift:489`). It routes only extension OAuth, `onecast://dock/…`
  and extension deep links. It is one-way: nothing comes back.
- **`settings.json` mirror** (`docs/features/settings-file.md`): live, two-way, validated. A good way
  to set up preferences declaratively.
- **Harnesses** (`Scripts/run-tests.sh`, ~120 `Tests/*.swift`): fast and pure, but they cover `Model/`
  only, not views or wiring.
- **`Signposts`** (`Platform/Signposts.swift`): perf intervals for Instruments, not for agents.
- **`AIToolBridge` / `AIToolHelper` / `ComputerController`**: the app already *is* an MCP-tool host for
  its own AI chat (computer use, browser relay). That code drives *other* apps on the AI's behalf, but
  its transport is exactly what an agent channel needs.
- **173 `accessibilityLabel`s**, but **0 `accessibilityIdentifier`s** and untitled panels.

## 2. Why "just use ComputerUse" is slow here in particular

1. **The surface is a non-activating floating panel** (`PalettePanel: NSPanel`), opened by a global
   Carbon hotkey. A synthetic event goes to whatever is focused at that moment, so every action needs
   a settle delay.
2. **Lists change underneath you**: search-as-you-type, network-populated extension lists, async file
   search. Without a "ready" signal, the only safe choice is a generous sleep.
3. **State that matters is invisible**: which row is *selected* versus *hovered* (UI_TESTS §7, "Selection
   indistinguishable from hover"), whether a footer chip's key is live, what the back stack is, why a
   list is empty (no results or a swallowed 429).
4. **15 different panel classes** (`PalettePanel`, `MenuPanel`, `DialogPanel`, `HUDPanel`,
   `NotesPanel`, `DockPanel`, `DockFloatingPanel`, `NotificationPanel`, `QuickActionPanel`,
   `CameraPanel`, `ExtensionListPanel`, `PopOutWindowPanel`, `DictationPanel`, `AppWindow`, the drop
   guide), all untitled to AX. A screenshot cannot tell them apart.
5. **Extensions are untrusted JS rendered natively**: when one misbehaves, the cause is in the JS
   runtime (console output, render tree, a rejected promise), and none of that is visible from outside.

## 3. Design principles for an agent channel (fitted to this codebase's rules)

- **Debug-only, compiled out of Release.** Wrap the whole thing in `#if DEBUG` (or a dedicated
  `AGENT_CONTROL` compilation condition in `project.yml`'s Debug config). It is a remote-control
  surface, the same kind of capability `AGENTS.md` keeps out of `settings.json` and backups. Nothing in
  a shipped build should ever listen.
- **`AppCore` owns it**, wired in `start()`, as one `AgentControlServer` (a "Server" suffix fits; see
  standards.md naming). No singleton, no second actor: `@MainActor`, the same as `AIToolBridge`.
- **Pure request/response types in `Model/`** (`AgentCommand`, `AgentSnapshot`), Foundation-only, with
  a new `Tests/agent-control-test.swift` harness pinning the JSON shape. The harness rule then enforces
  it by compilation.
- **Local only, authenticated.** Use a Unix domain socket (or loopback listener) under
  `~/Library/Application Support/com.onecast.app.dev/agent/`, mode `0600`, plus a per-launch token in
  a handshake file. This is the `AIToolBridge` + `AIToolTokenLedger` shape again.
- **Read the coordinators; don't add a second path.** Actions call the same `PaletteCoordinator`,
  `SettingsCoordinator`, `ExtensionCoordinator` methods a hotkey or click calls. If an action needs a
  method that doesn't exist yet, add it to the coordinator, so the agent can never reach a state a user
  can't.
- **Deterministic beats fast.** Every mutating call returns only once the state it caused is observable,
  or takes an explicit `waitFor`.

## 4. Gap analysis: what to add

### 4.1 Semantic state snapshot (highest value)

`GET state` returns JSON a model can reason over directly, in place of a screenshot:

```jsonc
{
  "build": { "bundleID": "com.onecast.app.dev", "commit": "5822722", "launchedAt": "…" },
  "palette": {
    "visible": true, "mode": "launcher", "aiBar": false, "collapsed": false,
    "query": "stock", "selection": 2,
    "backStack": ["launcher"],
    "rows": [
      { "index": 0, "section": "Results", "id": "ext:stocks/quotes", "kind": "extensionCommand",
        "title": "Stock Quotes", "subtitle": "Stocks", "selectable": true },
      …
    ],
    "footer": [ { "label": "Open", "key": "↵", "enabled": true }, { "label": "Actions", "key": "⌘K" } ],
    "openMenu": null,
    "emptyState": null,
    "frame": [1844, 416, 750, 475]
  },
  "windows": [ { "id": "palette", "class": "PalettePanel", "level": 8, "key": true, "frame": […] },
               { "id": "dock.main", "class": "DockPanel", … } ],
  "focus": { "firstResponder": "NSTextView(paletteField)", "frontmostApp": "com.apple.Terminal" },
  "extension": { "running": "stocks/quotes", "renderTreeDepth": 4, "lastError": null },
  "errors": [ { "at": "…", "category": "Extensions", "message": "HTTP 429 from …" } ]
}
```

Implementation notes:

- `PaletteState` is `@Observable` and already holds `mode`, `query`, `selection`, `backStack`,
  `clipboardFilter`, `aiBar` and the rest. Serialising those is direct.
- **Rows are the hard part**: each of the ~30 `PaletteScreen` conformances renders its own list.
  Add one optional requirement, e.g. `var agentRows: [AgentRow] { get }`, with a default empty
  implementation, then fill it in screen by screen, starting with the launcher, clipboard, extension
  list and plugin. `PaletteRowIndex` already gives the flat index → section/offset mapping to reuse.
  - Extensions are the exception: per AGENTS.md, an extension's rows must be produced **inside
    `Features/Extensions/`**. The extension screen supplies its own `agentRows` from its render tree,
    and the palette only relays them as opaque data, the same "opaque box" rule `LauncherScreen`
    follows for `ExtensionArgumentsAccessory`.
- Footer chips: expose whatever the footer view is built from (the label/key list), so a "chip shown for
  an inert key" (UI_TESTS §7) becomes a JSON assertion.
- Windows: enumerate `NSApp.windows`, report class name, an assigned stable `agentID`, level,
  `isKeyWindow`, `isVisible`, frame and `occlusionState`.

### 4.2 In-process actions

All `@MainActor`, all going through existing coordinators:

| Action | Maps onto |
| --- | --- |
| `show(mode, query?)` / `hide()` / `toggle()` | `PaletteCoordinator.showPalette(mode:)`, `togglePalette(mode:seeding:)`, `hidePalette` |
| `setQuery(text)` | `PaletteState.query` (the same path typing takes, including `queryRewriteToken`) |
| `key(name, modifiers)` | build an `NSEvent` and send it to `PalettePanel.sendEvent` / `performKeyEquivalent`, so it is the real key path with no global CGEvent, no Accessibility grant and no focus race |
| `select(index)` / `activate(index or id)` | selection + the screen's activate path, or `PaletteMenuContent.activate` for open menus |
| `openSettings(tab, anchor?)` | `SettingsCoordinator` + `SettingsTab` / `SettingsAnchor` |
| `runHotKeyAction(action)` | the `HotKeyAction` dispatch, so any bound behaviour can be triggered without binding a chord |
| `runEntry(id)` | `AppEntry` activation by ID: apps, quicklinks, extension and plugin commands |
| `openURL(url)` | `AppCore.handleOpenURL`, for parity with deep links |
| `popToRoot()` / `closeScreen()` | the existing methods |
| `setAppearance(light/dark/system)` | `AppAppearance`, to check both branches of `Theme` in one run |
| `dialog.answer(button)` | `DialogController`, so a confirm dialog doesn't block a run |

Sending key events into the panel is the important design choice. It keeps tests of the real keyboard
contract (Escape unwinding, ⌫ on an empty field, ⇧↵ in the AI composer) while dropping the 2 s settle
time and the dependency on which app is frontmost. Keep the `osascript` path from UI_TESTS.md as a
final check for the global hotkey itself, which only a real chord can test.

### 4.3 Waiting without `sleep`

`waitFor(condition, timeout)` evaluated on main after each observation change (or polled every 16 ms):

- `palette.visible`, `mode == X`, `rows.count >= N`, `row[i].title contains`, `extension.idle`,
  `network.idle` (in-flight request count per feature), `animations.idle` (the `MenuPanelMotion`
  durations are known).

Every mutating action takes an optional `waitFor`, so "type, then wait until rows change" is one call.
This removes UI_TESTS §3's timing table entirely.

### 4.4 Capturing a specific window

`capture(windowID, scale?, appearance?)` → PNG path:

- First choice: `SCScreenshotManager` with an `SCContentFilter(desktopIndependentWindow:)` for that
  one `NSWindow` (ScreenCaptureKit is already linked for `ComputerController`). It captures glass and
  vibrancy accurately and needs Screen Recording for the Dev app, a one-time grant that persists
  thanks to the stable signing identity.
- Fallback without a grant: `NSView.bitmapImageRepForCachingDisplay` on the content view. Fine for
  layout checks, but blurs and glass won't match the screen; label it as such in the response.
- Return the frame and the row frames with it, so an agent can crop or annotate "row 3" without
  vision guesswork. UI_TESTS §4's "look at the image" rule still applies to visual judgements.

### 4.5 Logging and error visibility

Today: 5 `Logger`s, inconsistent subsystems (`com.onecast`, `com.onecast.perf`), 618 `try?`.

- Add `Platform/Log.swift`: one `Logger` per feature category, with the subsystem set to
  `Bundle.main.bundleIdentifier` so Dev and stable stay separate, as the dev-channel rule requires.
  An agent can then run
  `log stream --level debug --predicate 'subsystem == "com.onecast.app.dev"'` in the background, or
  `log show --last 2m …` after a run.
- In Debug, also write each entry into an in-memory ring buffer (~2000 entries) that `state.errors` and
  a `logs(since:, category:)` action return, so no `log` CLI parsing is needed.
- Turn the **high-traffic `try?` sites into logged failures**: network fetches (`CurrencyRateStore`,
  extension `fetch`, update check, AI providers), persistence loads (snippets, quicklinks, clipboard
  DB) and plugin compile/load. UI_TESTS §7's "half the watchlist had no price" was a `try?` swallowing
  a 429. Not every one needs changing; the ones whose failure shows up as an empty UI do.
- This replaces UI_TESTS §5's temporary `debugLog`-to-`/tmp` pattern with permanent, structured,
  zero-cost-in-Release logging.

### 4.6 Extension and plugin debuggability

Raycast extensions run in JavaScriptCore, plugins are compiled Swift dylibs. Both are opaque from
outside today.

- **Extensions**: capture `console.*` and unhandled rejections per command into the ring buffer
  (category `Extensions/<ext>/<cmd>`). Expose `extension.renderTree()`, the current List/Detail/Form
  tree as JSON, the same structure the native renderer consumes. That splits "the JS produced the
  wrong tree" from "we rendered a correct tree wrongly" in one call. Also expose
  `extension.reload(id)`, since the folder is watched but an agent can't see when the reload finished.
- **Plugins**: report the loaded dylib path plus its mtime and hash next to the source file's
  mtime. That catches the "stale dylib answering the keys" register entry automatically. Expose
  compile errors from the plugin build step as structured diagnostics instead of a HUD string.

### 4.7 Accessibility identifiers and window titles

Still worth doing, even with the control channel. ComputerUse-style tools, XCUITest (if ever added)
and real assistive tech all use them, and they're cheap.

- `setAccessibilityIdentifier` / `setAccessibilityTitle` on every `NSPanel` subclass
  (`"onecast.palette"`, `"onecast.dock.<id>"`, `"onecast.hud"`, …). Today `get name of windows`
  returns blanks.
- `.accessibilityIdentifier` on the palette search field, each row (`"palette.row.<entryID>"`), footer
  chips, the Settings sidebar items (`"settings.tab.<tab>"`) and dialog buttons.
- Mark the selected row with `.accessibilityAddTraits(.isSelected)`, so AX itself can answer "which
  row is selected".
- Note the extension rule: identifiers inside extension views are set in `Features/Extensions/` and
  namespaced (`"ext.row.<index>"`), never through a shared helper.

### 4.8 Deterministic launch and state

- **Launch arguments for agent runs** (Debug only): `-AgentControl YES` to start the server,
  `-SkipOnboarding YES`, `-PaletteHotKey cmd+space`, and `-SeedFixture <name>` to load a canned
  clipboard history, snippets or quicklinks from `Tests/` fixtures. `UserDefaults` already reads
  `-key value` arguments, so most of these need no parsing.
- **A disposable data root**: an environment variable such as `ONECAST_DATA_ROOT` honoured by
  `AppPaths` in Debug only, so an agent can run against a throwaway state and never touch the
  developer's real Dev-channel clipboard or notes. This is optional and should be weighed against the
  "no flags" posture. It is a Debug test seam, not a compatibility layer.
- **A reset action**: `resetState(scope)` to clear caches (the "run once with cache cleared" check in
  UI_TESTS §6) without hunting for `defaults` keys.

### 4.9 Tooling around the app

- `Scripts/dev-run.sh`: the Debug `xcodebuild`, the signing-identity check from AGENTS.md
  (`security find-identity` vs `codesign -dvv`), quit `Onecast Dev`, relaunch, and wait for the agent
  socket to answer `ping`, not `sleep 6`. This turns the three non-negotiables (relaunch, signing, no
  stale build) into one command that can't be half-run.
- `Scripts/onecastctl` (or a tiny Swift CLI target, like `AIToolHelper`): `onecastctl state`,
  `onecastctl key down`, `onecastctl capture palette out.png`. Usable from any shell or agent, no MCP
  required.
- **MCP server**: register the same channel as a stdio MCP server in the repo's `.mcp.json`. The
  `AIToolHelper` binary already relays stdio MCP to a loopback token-gated listener, so a second
  "toolset" mode or a sibling helper reuses it. Claude Code then gets `onecast_state`,
  `onecast_key`, `onecast_capture` and the rest as native tools.
- **A project skill** (`.claude/skills/onecast-drive/SKILL.md`) that teaches the loop: `dev-run.sh` →
  `state` → act → `waitFor` → `capture` → compare, plus when to fall back to `osascript` (global
  hotkey only). The generic `run` skill looks for exactly such a project skill first.
- Update `custom_docs/UI_TESTS.md` §3–§5 to the new loop once it lands. The §7 register stays, and
  many of its "Check" lines become scripted `waitFor` + JSON assertions.

## 5. Suggested phasing

| Phase | Deliverable | Rough size | Payoff |
| --- | --- | --- | --- |
| **0** | `Scripts/dev-run.sh` (build + sign check + relaunch + readiness); window AX titles/identifiers | small | removes the most common stale-build and "which window" mistakes immediately |
| **1** | `AgentControlServer` (Debug-only UDS + token), `ping`, `state` with palette state, windows, focus; `onecastctl` | medium | agents stop screenshotting just to learn the mode, query or selection |
| **2** | actions: `show`, `setQuery`, `key` (in-panel `NSEvent`), `select`, `activate`, `openSettings`, `runEntry`, `hide`; `waitFor` | medium | driving drops from seconds per step to milliseconds, with no focus races |
| **3** | `agentRows` on the launcher, clipboard, file search, emoji, plugin and extension screens; footer chips | medium, incremental per screen | assertions on content, not pixels |
| **4** | `Platform/Log` + ring buffer + `logs` action; convert the network and persistence `try?` sites | medium | "why is it empty" answerable without a rebuild |
| **5** | `capture(window)` via ScreenCaptureKit + row frames; appearance toggle | small | exact, labelled captures for the visual checks that remain |
| **6** | extension console capture + `renderTree` + reload signal; plugin dylib freshness | medium | debugging third-party extensions from the outside |
| **7** | MCP registration via the `AIToolHelper` pattern; project skill; UI_TESTS rewrite | small | turns it all into first-class agent tools |

Phases 0–2 alone cover most of the speed problem. Phases 3–6 turn "looks wrong" into "this row
reports `selectable:false`" or "`fetch` logged a 429".

## 6. Risks and constraints to respect

- **Never in Release.** Gate both the code and the `project.yml` setting. Add a lint or release check
  (`Scripts/verify-signature.sh` or `lint.sh`) that fails if the agent symbols appear in a Release
  binary (`nm | grep AgentControl`).
- **Secrets**: the snapshot must never include clipboard contents, note text, snippet bodies, AI chat
  text or Keychain values unless asked for explicitly, and redaction should follow the existing
  `RedactedText` rules. Rows get titles and IDs, and clipboard rows get kind and length only, unless
  `includeContent: true`.
- **No new architecture violations**: no second actor, `AppCore` owns the server, `Model/` stays
  Foundation-only, extension-specific code stays in `Features/Extensions/`, and actions go through
  coordinators rather than poking views.
- **Doesn't replace real-input testing.** The global hotkey, Carbon registration, `CommandEscapeTap`,
  Hyper key and snippet keystroke listening go through system event taps that an in-panel `NSEvent`
  bypasses. Keep a short `osascript` smoke pass for those.
- **Maintenance cost of `agentRows`**: each new screen should provide it. A default empty
  implementation keeps that optional, and `state` can report `"rows": null, "reason": "screen has no
  agentRows"` so the gap is visible instead of silent.

## 7. Open questions for the maintainer

1. Unix domain socket or loopback TCP? A socket file with `0600` permissions is simpler to secure.
   `AIToolBridge` uses Network.framework loopback, so reusing it favours TCP.
2. Should the MCP surface reuse `AIToolHelper` (one helper, two toolsets) or get its own helper target?
   Reusing keeps `project.yml` small. A separate target keeps the AI chat's trust boundary untouched.
3. Is a Debug-only `ONECAST_DATA_ROOT` seam acceptable under the "no flags" posture, or should agent
   runs use the real Dev-channel data plus `resetState`?
4. Should the channel also accept a `raw eval`-style escape hatch (e.g. run a named debug closure
   registry)? Recommendation: no. Keep the action list closed and add actions as they're needed.
