# Native plugins

Onecast loads **native Swift plugins** — SwiftUI the app **compiles from source** and renders into
the command palette. This is separate from [extensions](../docs/features/extensions.md), which run
Raycast's JavaScript in JavaScriptCore. A plugin is first-party Swift the user drops in and trusts;
the develop → build → install workflow is [plugins_and_extensions.md](../docs/plugins_and_extensions.md).

**Trust model.** A plugin runs **in-process, unsandboxed, with the app's full privileges**
(Accessibility, Automation, the lot) — the same trust model BetterTouchTool states for its Swift
plugins. Only install plugins whose source you have read. Because of that: `pluginsEnabled`
defaults off, confirms before it turns on, and never rides a settings backup (importing one can
never silently arm plugin loading); the app ships the
`com.apple.security.cs.disable-library-validation` entitlement so a user-built, ad-hoc-signed dylib
can load under the hardened runtime.

> This is a fork-local feature. See [CUSTOM.md](CUSTOM.md) for how it is carried and where
> plugin sources live.

## Invariants

- **The contract is the framework, and there is exactly one copy.** `OnecastPluginKit.framework`
  is built by this project and embedded in the app. Every plugin compiles against *that* embedded
  framework, so a plugin's `OnecastPlugin` and the host's are the **same** type across the `dlopen`
  boundary. Two copies would give two unrelated protocols and every cast would fail.
- **The app compiles a plugin from source, on demand.** `PluginBuilder` shells out to `swiftc`
  (through `xcrun`) against the embedded framework, ad-hoc signs the dylib, and caches it keyed on a
  source fingerprint — no author-run build step, and no prebuilt dylib in the folder.
- **`PluginManager` is the sole owner of the running session**, wired on `AppCore` in `start()`.
  It never touches a window; `PluginCoordinator` owns every palette move.
- **A plugin surfaces as exactly one launcher row** (`AppEntry.Kind.plugin`). Activating it enters
  `PaletteMode.plugin`, where the plugin owns the whole screen. Its own rows, children and surfaces
  live inside that mode — they never leak into the root launcher index.
- **The API layer may use SwiftUI.** `OnecastPluginKit` is not under `Features/*/Model/`, so the
  purity rule does not apply — `PluginResult`/`PluginContext` are still Foundation-only value types,
  but the contract vends `AnyView`.

## How it fits together

```
┌ Plugin sources (the author writes; the app builds) ──────────────┐
│  final class MyPlugin: NSObject, OnecastPlugin { … }             │
│  @_cdecl("onecastPluginCreate") -> OnecastPluginRuntime.export  │
│  links → @rpath/OnecastPluginKit.framework                       │
└───────────────────────────────┬──────────────────────────────────┘
                                 │ dlopen + dlsym("onecastPluginCreate")
┌ Host (Onecast) ──────────────▼──────────────────────────────────┐
│ PluginBuilder  swiftc vs. the embedded framework, sign, cache dylib│
│ PluginLoader   dlopen, cast the opaque pointer to OnecastPlugin  │
│ PluginCatalog  scans …/plugins/<name>/ (manifest + .swift) → Install│
│ PluginManager  @Observable session: rows, children, surface, run  │
│ PluginScreen   a PaletteScreen; hosts the plugin's list or AnyView │
│ PluginCoordinator  launch, navigate, exit, consent, uninstall     │
│ AppIndex.setPluginCommands → one AppEntry(.plugin) per install     │
└───────────────────────────────────────────────────────────────────┘
```

Files: `OnecastPluginKit/` (the framework), `Onecast/Features/Plugins/` (the host feature).

Installed plugins live at `~/Library/Application Support/<bundle id>/plugins/<name>/`, each a
folder with a `manifest.json` and the `.swift` sources beside it. The bundle id is per channel —
`Onecast Dev.app` is `com.onecast.app.dev`, a release build is `com.onecast.app` — so a dev build
never shares plugins with a release build. Built dylibs are cached separately under
`~/Library/Caches/<bundle id>/PluginBuilds/`.

## The plugin contract

`import OnecastPluginKit`. The full surface:

```swift
@MainActor public protocol OnecastPlugin: AnyObject {
    init()
    static var metadata: PluginMetadata { get }
    func rootSurface(context: PluginContext) -> AnyView?                                   // default: nil
    func results(for context: PluginContext) -> [PluginResult]                            // default: []
    func children(of resultID: String, context: PluginContext) async -> [PluginResult]   // default: []
    func perform(resultID: String, context: PluginContext) async -> PluginActionResult    // default: .close
    func surface(for resultID: String, context: PluginContext) -> AnyView                 // default: EmptyView
}
```

- `PluginMetadata(name:subtitle:icon:)` — the launcher row's title, subtitle and SF Symbol.
- `PluginContext` — `query` (the live palette text), `frontmostAppBundleID`, `finderSelection`.
- `PluginResult(id:title:subtitle:trailingText:icon:keywords:action:)` — one row.
  - `PluginIcon` — `.symbol(String)` or `.file(URL)`.
  - `PluginAction` — what activating the row does:
    - `.run(id:)` → the host calls `perform`, honours `PluginActionResult(closesLauncher:message:)`.
    - `.children(id:)` → the host calls `children` and pushes the returned rows.
    - `.surface(id:)` → the host shows your SwiftUI view as the **whole panel**: the palette hides
      its own header, footer and drag strip, so the surface draws its own chrome if it wants any.
    - `.openURL(URL)` → the host opens it and closes the launcher.
    - `.none` → inert.

`results(for:)` is re-asked on every keystroke — filter on `context.query` yourself. Pushed child
lists are filtered by the host. A surface owns the entire panel and its own keyboard: wrap it in a
`PluginScaffold` (below), which claims Escape, ⌘K and the list keys through a local monitor ahead of
the host, so navigation never depends on which control holds first responder.

**A surface-only plugin** returns a view from `rootSurface(context:)` and opens straight into it —
no root row list, no `results(for:)`. The whole plugin is that one SwiftUI screen (see the
stock-quotes plugin). Return nil to keep the row model instead; a plugin does one or the other.

### A surface's scaffold

A `.surface` owns the whole panel, so the framework hands it the chrome the host no longer draws.
Wrap the surface's body in
`PluginScaffold(navigator:primaryActionLabel:commands:commandTitle:listKey:) { root }`:

- `PluginNavigator` — the surface's own view stack. `push(title:_:)` drills in; **Escape** pops it,
  and at the root Escape leaves the plugin (the scaffold calls the host-injected
  `EnvironmentValues.pluginExit`). No back chevron to wire, and no Escape monitor to install.
- `commands:` / `commandTitle:` — the `[PluginCommand]` and heading for the **⌘K** palette pinned
  bottom-right. `PluginCommand(title:subtitle:icon:shortcut:action:)`; re-read each time it opens.
- `listKey:` — `↑/↓/←/→/Return` (`PluginListKey`) for a list on the current view, read from the
  scaffold's own monitor so it works whatever holds focus. Return true when you consumed the key;
  ←/→ can drive a second axis, or fall through to the search caret when you return false.
- `escape:` — **Escape**, offered to the surface before the stack pops and before the plugin is
  left, so a surface unwinds a step at a time: a live search clears back to its list, and only then
  does a further press go back or out. Return true when you consumed it.
- A **bare backspace** is the surface's own: everywhere else in the palette it takes Escape's back
  step once the query is empty, but a surface owns its search field and the host cannot see whether
  that field still holds text, so the key is left to it. Escape is the way back out. A plugin still
  on the row model keeps the palette's rule, stepping back one of its own list levels per press.

The scaffold's footer is the shared `ActionBar` from `OnecastPluginKit` — the same bar the launcher
and JS extensions render (the app builds it in `RootPaletteView.bottomBar` with a Theme-derived
`ActionBarStyle`; the scaffold uses the default). `.standard` fills it from the surface's Back state,
`primaryActionLabel` and commands; a surface passes `footer: .hidden` for a full-bleed view or
`.custom { AnyView(…) }` to draw its own. It floats over a bottom fade so content dissolves under it
— give scroll views `.contentMargins(.bottom, …)` so the last row clears it.

The full authoring guide — focus/layout gotchas and a worked example — lives beside the plugins:
`onecast_addons/plugins/SWIFT_PLUGINS.md`. The worked row-model example is
[`hello`](../../onecast_addons/plugins/hello/) — a run action, a drill-in child list, a SwiftUI
surface and an external link, all in one plugin. The worked surface-only example is
[`stock-quotes`](../../onecast_addons/plugins/stock-quotes/).

## Build a plugin

There is no build step you run — the app compiles the plugin. A plugin is a folder with a
`manifest.json` and its `.swift` sources; drop it into the plugins directory and Onecast builds it
against its own embedded framework. The end-to-end workflow, the caching and the toolchain
requirement are in [plugins_and_extensions.md](../docs/plugins_and_extensions.md).

**Folder layout** — the source sits beside the manifest (any `.swift` under the folder is compiled
as one module; a `Sources/` tree also works):

```
my-plugin/
├── MyPlugin.swift
└── manifest.json
```

**A minimal plugin** — a surface-only shape (`MyPlugin.swift`):

```swift
import AppKit
import SwiftUI
import OnecastPluginKit

final class MyPlugin: NSObject, OnecastPlugin {
    static let metadata = PluginMetadata(name: "My Plugin", subtitle: "A native SwiftUI plugin", icon: "star")

    // NSObject's init() does not satisfy the protocol requirement on its own — declare it.
    override init() { super.init() }

    // Return a view to open straight into a full-panel SwiftUI surface.
    func rootSurface(context: PluginContext) -> AnyView? {
        AnyView(RootView())
    }
}

private struct RootView: View {
    @State private var navigator = PluginNavigator()

    var body: some View {
        // PluginScaffold gives you the shared footer, Escape-to-back, a ⌘K palette
        // and focus-independent list navigation. A surface owns the whole panel.
        PluginScaffold(navigator: navigator, primaryActionLabel: "") {
            Text("Hello from a native plugin")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// The host's only entry point — export exactly this symbol, verbatim.
@_cdecl("onecastPluginCreate")
public func onecastPluginCreate() -> UnsafeMutableRawPointer {
    OnecastPluginRuntime.export { MyPlugin() }
}
```

For the row-model shape instead, implement `results(for:)` and `perform(resultID:context:)` per
the contract above — see `hello`.

**The manifest** (`manifest.json`) — the launcher row's identity:

```json
{
  "name": "My Plugin",
  "identifier": "com.example.my",
  "subtitle": "A native SwiftUI plugin",
  "icon": "star"
}
```

`name` and `identifier` are required; `subtitle`, `icon` (an SF Symbol) and `module` (the Swift
`-module-name`, derived from `name` when omitted) are optional.

**Install, enable, run.** Copy the folder's contents into the per-channel plugins directory:

```sh
DEST="$HOME/Library/Application Support/com.onecast.app.dev/plugins/my-plugin"
mkdir -p "$DEST" && cp manifest.json MyPlugin.swift "$DEST/"
```

Open Onecast → **Settings → Plugins** and turn plugins on (it confirms the first time — plugins are
unsandboxed native code), then summon the palette and search for the plugin by name. Activating its
row enters the plugin's own mode, where it owns the whole screen. Building needs a Swift toolchain
(Xcode or the Command Line Tools); a compile error surfaces in the palette where the plugin would run.

## Installing and editing while Onecast runs

`PluginManager` watches the plugins folder with a `DispatchSourceFileSystemObject` (the same idiom
as `SnippetsStore`), so a plugin dropped in — or a source file edited — appears and rebuilds within
a moment, no relaunch needed. The rescan is debounced, so a burst of file copies from one install
collapses into a single refresh, and each installed plugin is pre-warmed off-main so launching it is
instant.

A rebuild needs no app relaunch: `PluginLoader` maps a **content-addressed** copy of the built dylib,
so fresh bytes load on the next open. The one holdover — a plugin already running *this session*
keeps its mapped image until you leave it and reopen, because `dlopen` reference-counts and the old
image stays until the session is torn down.

## Pop-out windows

A plugin surface can be **popped out into its own standalone window** — the ⌘K palette's **Pop Out**
command, beside Add to Main Menu. The window renders only the plugin's own view — no palette header,
footer or scaffold — over the same backdrop the launcher draws. It is borderless, resizable, moved by
dragging its background and closed with ⌘W; a bottom-right ⌘K palette carries its window controls
(show on all spaces, keep in front, pin to desktop, close).

**Pin to Desktop** (⌘D) is the widget mode: the window sits one level above the desktop icons, behind
every app window. An all-spaces window at `.normal` level is drawn over the arriving space's windows on
each space switch before it drops back — `.stationary` does not help, only the level does. Pin and
keep-in-front are two values of the one window level, so turning either on turns the other off.

Each pop-out loads its **own** plugin instance, independent of the palette's running session and of
every other window, so several float at once — keyed by `PluginRoute`, so an ADBE chart and an MSFT
chart are distinct windows.

Opt a surface into a bare window body by reading `PluginContext.presentation`:

```swift
func rootSurface(context: PluginContext) -> AnyView? {
    if context.presentation == .window {
        return AnyView(MyChart(route: context.route))   // bare — no PluginScaffold
    }
    return AnyView(MySurface(…))                          // in-palette: wrap in PluginScaffold
}
```

`.window` needs a `PluginRoute` (the scaffold's `route:` closure), which both identifies the window
and restores its content; a surface with no route offers no Pop Out.

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| Build fails: "No Swift toolchain found" | Install Xcode or the Command Line Tools (`xcode-select --install`). |
| Plugin row never appears | Plugins disabled (Settings → Plugins), or the folder under `…/Application Support/<bundle id>/plugins/<name>/` has no `manifest.json` or no `.swift` source. |
| Build fails with a compiler error | The diagnostic shows in the palette where the plugin would run — fix the source; the watcher rebuilds on save. |
| Rebuild not reflected in a running plugin | Its image is still mapped for this session — leave the plugin and reopen it (no app relaunch needed). |
| "OnecastPluginKit's module interface is missing" | The app build didn't restore the embedded interface — rebuild Onecast (the `project.yml` post-build step does it). |
