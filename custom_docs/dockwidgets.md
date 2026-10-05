# DockWidgets

A **DockWidget** is a live tile in a custom dock — a clock, a meter, a counter — written in
SwiftUI and **compiled from source by Onecast**, exactly as a [native plugin](plugins.md) is. The
built-in widgets implement the same protocol, so a dock hosts both one way. A DockWidget is a
public Swift API: `OnecastDockWidget`, in `OnecastPluginKit`.

> This is a fork-local feature; see [CUSTOM.md](CUSTOM.md). Authors need only a Swift toolchain
> (Xcode or the Command Line Tools). A worked example lives at
> [`onecast_addons/dockwidgets/hello`](../../onecast_addons/dockwidgets/hello/).

**Trust model.** A DockWidget runs **in-process, unsandboxed, with Onecast's full privileges**
(Accessibility, Automation, files, network) — the same model as plugins, and it gets no narrower
because the code draws a tile. Only install widgets whose source you have read. Because of that
`dockWidgetsEnabled` defaults off, confirms before it turns on (`DockCoordinator.setDockWidgetsEnabled`),
never rides a settings backup, and only has an effect while Docks itself is on. Built-in widgets
need no consent: they ship inside the app.

## Invariants

- **One framework, one copy.** A widget compiles against the `OnecastPluginKit.framework` embedded
  in the app (`PluginBuilder` — the same machinery plugins use, with its own cache folder), so the
  host's `OnecastDockWidget` and the widget's are the same type across the `dlopen` boundary.
- **One object per instance.** The host calls the widget's entry point once for every instance on a
  dock, so a widget keeps its state in its own properties. Two copies of one widget on two docks
  never share a timer, a counter or a cache.
- **`DockWidgetManager` is the sole owner** of widget objects, reached as
  `core.dockCoordinator.widgets`. A view never constructs a widget; it asks the manager.
- **Preferences are per instance** and live in the host's defaults under
  `dockwidget.<instance UUID>.<name>`; removing the instance deletes every key under that prefix.
- **Third-party loading is consent-gated.** While it is off nothing is scanned, compiled or watched,
  no third-party object exists, and a saved tile reads as *unavailable*.

## How it fits together

```
┌ Widget sources (the author writes; the app builds) ──────────────┐
│  final class MyWidget: OnecastDockWidget { … }                   │
│  @_cdecl("onecastDockWidgetCreate") -> OnecastDockWidgetRuntime   │
│  links → @rpath/OnecastPluginKit.framework                        │
└───────────────────────────────┬──────────────────────────────────┘
                                │ dlopen once per build, dlsym + create() per instance
┌ Host (Onecast) ──────────────▼──────────────────────────────────┐
│ DockWidgetCatalog  scans …/dockwidgets/<name>/ → DockWidgetInstall │
│ PluginBuilder      swiftc vs. the embedded framework, sign, cache  │
│ PluginLoader       content-addressed dlopen, entry-point lookup    │
│ DockWidgetManager  library, live objects, builds, folder watcher   │
│ DockWidgetTileView the tile in its slot, or a placeholder          │
│ DockWidgetPreferencesEditor / DockWidgetsSettingsSection (Settings)│
└───────────────────────────────────────────────────────────────────┘
```

Files: `OnecastPluginKit/DockWidgetKit.swift` (the public API),
`Onecast/Features/Docks/{Model/DockWidgetManifest.swift, Service/DockWidgetCatalog.swift,
Service/DockWidgetManager.swift, Widgets/*.swift}` and the shared build/load code in
`Onecast/Features/Plugins/Service/`. `Tests/dockwidget-catalog-test.swift` pins the manifest and the
scan rules.

## Folder layout

Installed widgets live at `~/Library/Application Support/<bundle id>/dockwidgets/<name>/`, each a
folder with a `manifest.json` and the `.swift` sources beside it (any `.swift` under the folder is
compiled as one module; a `Sources/` tree works; `build/` and `.build/` are skipped). The bundle id
is per channel — `Onecast Dev.app` is `com.onecast.app.dev`, a release build `com.onecast.app` — so
a dev build never shares widgets with a release build. Built dylibs are cached under
`~/Library/Caches/<bundle id>/DockWidgetBuilds/<identifier>/`.

```
clock/
├── ClockWidget.swift
└── manifest.json
```

A folder without a readable `manifest.json`, with an unusable `identifier` or without a `.swift`
source is skipped, not an error: a half-copied install simply does not appear.

## The manifest

```json
{
  "name": "Clock",
  "identifier": "com.example.dockwidget.clock",
  "subtitle": "Time in another zone",
  "icon": "clock",
  "category": "Time",
  "sizes": ["compact", "wide"],
  "preferences": [
    {"name": "zone", "title": "Time zone", "type": "textfield", "default": "UTC"}
  ]
}
```

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | The library title. Also the source of the default module name. |
| `identifier` | yes | The stable id a dock stores for the widget. Not blank, not starting with `builtin.` (reserved for first-party), and unique: of two folders claiming one, the first by name wins. |
| `subtitle` | no | One line under the title in the library. Default empty. |
| `icon` | no | An SF Symbol for the library. Default `square.grid.2x2`. |
| `category` | no | The library's grouping. Default `Other`. |
| `sizes` | no | Any of `"compact"`, `"wide"`, `"expanded"`; the first is the size a new instance takes. Unknown strings are dropped, repeats collapse, and none left means `["compact"]`. |
| `module` | no | The Swift `-module-name`. Derived from `name` (alphanumerics only, never digit-first) when absent. Set it when two installed widgets or plugins would otherwise share a module name. |
| `preferences` | no | Per-instance settings; see below. |

Unknown keys are ignored, so a manifest written for a newer Onecast still loads. The manifest is read
before the code is built, so the library lists a widget while it compiles; once built, the metadata
the code reports (`DockWidgetMetadata`) is what the widget itself declares, and the two should agree.

## The protocol

`import OnecastPluginKit` (and `SwiftUI`). Every call runs on the **main actor**; push heavy or IO
work onto a `Task.detached` you `await`.

```swift
@MainActor public protocol OnecastDockWidget: AnyObject {
    init()
    static var metadata: DockWidgetMetadata { get }
    func tile(context: DockWidgetContext) -> AnyView                // the tile in the dock
    func popover(context: DockWidgetContext) -> AnyView?           // default: nil
    func didRemove()                                                // default: no-op
}
```

```swift
public struct DockWidgetMetadata {
    init(name: String, subtitle: String = "", icon: String = "square.grid.2x2",
         category: String = "Other", sizes: [DockWidgetSize] = [.compact])
}
public enum DockWidgetSize { case compact, wide, expanded }
public enum DockWidgetEdge { case bottom, left, right; var isVertical: Bool }

public struct DockWidgetContext {
    let instanceID: String            // the dock item's UUID
    let size: DockWidgetSize
    let edge: DockWidgetEdge
    let tileLength: CGFloat           // the dock's tile size, in points
    let preferences: DockWidgetPreferences
    let actions: DockWidgetActions
}
```

Export the type through the one entry point the host looks up, verbatim:

```swift
@_cdecl("onecastDockWidgetCreate")
public func onecastDockWidgetCreate() -> UnsafeMutableRawPointer {
    OnecastDockWidgetRuntime.export { MyWidget() }
}
```

### Sizes and edges

The host frames `tile(context:)` to its slot and clips it to the tile's rounded rectangle, **drawing
no background or chrome of its own** — fill the proposed frame and draw whatever surface you want.

| `size` | Slot along the dock | Across the dock |
|---|---|---|
| `.compact` | `tileLength` | `tileLength` |
| `.wide` | two tiles and the gap between them | `tileLength` |
| `.expanded` | four tiles and the three gaps between them | `tileLength` |

The gap is `0.12 × tileLength`, so a wide slot is `2.12 × tileLength` long and an expanded one
`4.36 ×`. On a side dock
(`edge.isVertical`) the axes swap: a wide tile is `tileLength` wide and `2.12 × tileLength` tall, so
lay out a stack instead of a row. Draw to the size, not to a constant: `tileLength` follows the
dock's tile-size setting. Only declare the sizes you draw well at; the library offers no others.

`tile(context:)` is **re-asked** whenever the context changes (size, edge, tile length) and after
every edit to one of the instance's preferences in Settings. Keep it live with your own
`@Observable` state — the host never polls — and read a preference *inside* `tile(context:)` or the
view's body, not once in `init()`, so an edit shows at once.

### Preferences

A manifest's `preferences` use the same schema as a plugin's: `name` (required), `title`,
`description`, `placeholder`, `type` (`textfield` — the default, also for an unknown type —
`checkbox`, `dropdown` with `options: [{"title", "value"}]`, `directory`) and `default` (a number is
stored as its text, so `"default": 5` reads back through `integer("minutes")`).

```swift
let zone = context.preferences.string("zone")        // text, dropdown, directory; nil when empty
let minutes = context.preferences.integer("minutes")  // a text value holding a whole number
let seconds = context.preferences.bool("seconds")     // a checkbox
context.preferences.set("45", for: "lastDuration")    // a value the widget itself changes
```

Values are stored **per instance** — two copies of a widget on two docks keep separate values — in
the host's defaults under `dockwidget.<instance UUID>.<name>`. The host registers each manifest
`default`, so an unset preference reads as its default (including a checkbox that defaults to
`true`). Clearing a text field returns it to the default. The dock editor shows one control per
preference for the selected tile. `set(_:for:)` may use names the manifest does not declare; those
keys are deleted with the instance too.

### Actions

`context.actions` is what a widget may ask the host to do. Every closure runs on the main actor.

| Closure | Does |
|---|---|
| `openURL(URL)` | Opens the URL with whatever the system registers for its scheme. |
| `launchApp(String)` | Launches or activates the app with that bundle identifier; a HUD says when there is none. |
| `runShortcut(String)` | Runs the Apple Shortcut of that name. It goes through Onecast's Apple Shortcuts feature, so that feature must be on, and the shortcut must exist. |
| `closePopover()` | Closes this instance's popover if it is open. |
| `openSettings()` | Opens Onecast's Settings on the Docks pane. |

A third-party widget has no other access to Onecast — no stores, no coordinators — though, being
native code in the same process, it can of course do anything the app can.

### Popover

A click on a tile asks the widget for `popover(context:)`. Return a view to show it beside the dock;
return nil (the default) and the click does nothing, so a tile that acts on click handles its own
taps. The host draws the popover's panel; give the view a **fixed size** (a width of roughly
260–320 pt works well) and its own padding, and no backdrop. Close it from inside with
`context.actions.closePopover()`.

### Lifecycle

1. The folder is scanned (on enabling, then whenever the folder or one of its files changes,
   debounced by 200 ms). A tile whose widget is not built yet shows a spinner.
2. Each new or edited widget is compiled off the main thread, one at a time, and cached by source
   fingerprint, so an unchanged widget never recompiles.
3. The built dylib is mapped once per build — a **content-addressed copy** in the temp directory, so
   a rebuild loads its fresh bytes without a relaunch.
4. The entry point is called once per instance, the first time its tile is drawn.
5. **`didRemove()`** is called once on an object that is going away: its tile was deleted from the
   dock, third-party widgets were switched off, the widget's folder was removed, or the widget was
   rebuilt (the live objects are replaced by fresh ones from the new code; their preferences
   persist). Stop timers and close files there.

A rebuild leaves the previous code mapped for the rest of the session, since a Swift image cannot be
unloaded safely; the runtime may log `Class … is implemented in both …` for the old and new copy of
your classes. It is harmless here — the old objects are dropped — and a relaunch clears it.

## A minimal complete widget

`~/Library/Application Support/com.onecast.app.dev/dockwidgets/wave/manifest.json`:

```json
{
  "name": "Wave",
  "identifier": "com.example.dockwidget.wave",
  "subtitle": "Counts waves",
  "icon": "hand.wave",
  "sizes": ["compact"]
}
```

`…/wave/WaveWidget.swift`:

```swift
import Observation
import OnecastPluginKit
import SwiftUI

@MainActor @Observable
final class WaveModel { var count = 0 }

final class WaveWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Wave", subtitle: "Counts waves", icon: "hand.wave", sizes: [.compact])

    private let model = WaveModel()

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(
            VStack {
                Image(systemName: "hand.wave.fill").font(.system(size: context.tileLength * 0.4))
                Text("\(model.count)").font(.caption).monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.08)))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(
            Button("Wave") { model.count += 1 }
                .padding(16)
                .frame(width: 200))
    }
}

@_cdecl("onecastDockWidgetCreate")
public func onecastDockWidgetCreate() -> UnsafeMutableRawPointer {
    OnecastDockWidgetRuntime.export { WaveWidget() }
}
```

The fuller [`hello`](../../onecast_addons/dockwidgets/hello/) example adds a wide size, a preference
and actions.

## Install, enable, use

1. Copy the folder into the dockwidgets directory:

   ```sh
   DEST="$HOME/Library/Application Support/com.onecast.app.dev/dockwidgets/wave"
   mkdir -p "$DEST" && cp manifest.json WaveWidget.swift "$DEST/"
   ```

2. In **Settings → Docks**, turn Docks on, then allow third-party DockWidgets (it confirms the first
   time). The installed list shows the widget, a spinner while it builds, and the compiler's output
   if it fails.
3. Add the widget to a dock from the dock editor's widget library and pick a size.

Editing a source while Onecast runs rebuilds it and refreshes every live instance; dropping a folder
in or deleting one is picked up the same way. The folder watcher follows each widget's files, not just
the top folder, so an in-place save counts.

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| Tile shows a lock | Third-party DockWidgets are off (or Docks is). Allow them in Settings → Docks. |
| Tile shows a spinner that never ends | The first build is still running, or the widget's folder was just dropped in — wait for the rescan. A hung `swiftc` shows in Activity Monitor. |
| Tile shows a warning triangle | Hover it for the first compiler error; the full output is in Settings → Docks → the widget's row. Fix the source; the watcher rebuilds on save. |
| Warning says the widget isn't in the DockWidgets folder | The folder was deleted, renamed or its manifest is unusable (blank `identifier`, or one starting with `builtin.`, or two folders claiming one id). |
| "No Swift toolchain found" | Install Xcode or the Command Line Tools (`xcode-select --install`). |
| "OnecastPluginKit's module interface is missing" | The app build did not restore the embedded interface — rebuild Onecast. |
| "has no onecastDockWidgetCreate entry point" | The source lacks the `@_cdecl("onecastDockWidgetCreate")` function, or it is not `public`. |
| "doesn't conform to OnecastDockWidget" | The entry point returned something that is not an `OnecastDockWidget` — export through `OnecastDockWidgetRuntime.export`. |
| Widget missing from the library | The folder has no `manifest.json`, no `.swift` source, or fails the manifest rules above. |
| A preference edit does nothing | The widget read it once in `init()`; read it inside `tile(context:)` or the view body. |
| Built-in widgets are fine but yours is slow | `tile(context:)` runs on the main actor each time the context changes; do not compute or fetch there. Keep results in `@Observable` state. |
