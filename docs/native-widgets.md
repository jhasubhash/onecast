# Native macOS widgets — feasibility

A design note, not a shipped feature. It records why Onecast renders plugin and extension surfaces as
floating pop-out windows rather than WidgetKit widgets, what a native widget *could* cover, and the one
concrete thing that blocks building it in this fork today.

## The question

Replace the pop-out panels — the standalone `NSWindow`s `PluginWindowController` opens — with proper
macOS widgets (Notification Center / desktop), and let plugins and extensions ship widgets alongside
the main add-on.

## Verdict

- **Plugin- or extension-authored native widgets: impossible.** Not hard — architecturally excluded by
  how WidgetKit runs, against how Onecast loads third-party code.
- **First-party WidgetKit widgets for Onecast's own built-in data: feasible**, and the right shape — a
  widget button can launch a plugin/extension command by deep link even though it can't render one.
- **Blocked in this fork right now** by signing: WidgetKit needs an App Group, and an App Group
  entitlement will not provision under local ad-hoc signing.

## Why third-party widgets can't work

A WidgetKit widget is a separate app-extension target (`.appex`,
`NSExtensionPointIdentifier = com.apple.widgetkit-extension`) **compiled and code-signed into the host
bundle at build time**, run by the system in a **separate, mandatorily-sandboxed process** (`chronod`).
Every load-bearing property of Onecast's plugin and extension model is banned in that process.

| Onecast today | WidgetKit extension process |
|---|---|
| Un-sandboxed — `com.apple.security.app-sandbox = false` in `Onecast.entitlements` | Sandbox mandatory |
| JIT on — `com.apple.security.cs.allow-jit`; JavaScriptCore compiles every extension command (`ExtensionHostBridge`) | No JIT; can't run Raycast extension JS |
| dlopens user-built dylibs — `com.apple.security.cs.disable-library-validation`; plugins are compiled dylibs the app `dlopen`s | Library validation enforced; can't load a user plugin |
| In-process live SwiftUI — `PluginWindowController` hosts an `AnyView` retaining a live plugin instance with closures | Static `TimelineProvider` snapshots; no live views, no closures, no scroll / text field / continuous callback |
| Widgets appear when a user installs an extension | The OS only knows widgets compiled and signed into the `.app` at build time |

So a Raycast extension's `RenderNode` tree, or a plugin's live SwiftUI, has no representation in a widget
process and no way to reach one. Installing an extension or dropping in a plugin dylib cannot register a
widget: there is no runtime registration path.

**The pop-out `NSWindow` is therefore the correct primitive, not a stopgap.** It is the only surface that
can host arbitrary, interactive, runtime-loaded code on the desktop. WidgetKit cannot replace it for
plugins or extensions, and this note is not an argument to try.

## What a first-party widget could cover

Native-Swift built-in features whose state is stable and ours: meetings / calendar, the floating note,
clipboard history, quicklinks and favorites, currency rates, calculator history. Shape if it is ever
built:

- A `OnecastWidgets.appex` target in `project.yml` — a `WidgetBundle` of `TimelineProvider`s,
  SwiftUI-only.
- An **App Group** container. The built-in stores today write JSON under
  `Application Support/<bundleid>`, which a sandboxed widget can't read; they would also write into the
  shared container, with `WidgetCenter.reloadTimelines` on change.
- Interactive tiles via `AppIntent` `Button` / `Toggle`. **A widget button can launch a plugin or
  extension command** by firing the existing deep link (`ExtensionDeepLink`): the plugin or extension
  still runs in-process in the main app, and the widget is only a signed first-party tile that triggers
  it. That is the honest bridge for "alongside the main add-on" — a launcher tile, never third-party
  widget UI.

## The blocker to clear first

App Groups need a real Team ID and a provisioning profile. This fork signs locally (see
[signing.md](signing.md) and [CUSTOM.md](../custom_docs/CUSTOM.md)), and an App-Group entitlement does
not work under ad-hoc signing. Until the build can sign with a real Team ID, there is nowhere for a
widget to read shared data from, so the widget target can't be built regardless of the design above.
Proving out the App-Group entitlement under this fork's signing is the prerequisite, not the widget
code.
