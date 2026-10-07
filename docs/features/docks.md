# Docks

Custom docks Onecast draws itself, several at once, beside or instead of the macOS Dock; saved
layouts for the macOS Dock; setups that switch everything in one go; and **DockWidgets**, live tiles
built-in or written by third parties against `OnecastPluginKit`. A port of Dockset's ideas, with
one difference by design: Dockset shows one custom dock at a time, Onecast any number.

## Invariants

- **`DockStore` is the one source of truth, and `DockCoordinator` its one writer.** Everything the
  feature persists is one `DockConfiguration` value under the `docks` defaults key; every edit is a
  transform through `DockStore.update`, sanitized before it lands, so a dangling layout, setup or dock
  reference is repaired rather than rejected. Views act through `core.dockCoordinator`, never the store.
- **Every on-screen consequence is re-projected from the configuration.** `DockCoordinator.applyEnabled()`
  runs on each store change and each flip of `docksEnabled` / `dockWidgetsEnabled`: panels reconcile,
  the macOS Dock is hidden or restored, the window observer arms or disarms, launcher rows refresh.
  Nothing else shows or hides a dock.
- **The macOS Dock is always put back.** Hiding records the user's own `autohide`, `autohide-delay`
  and `autohide-time-modifier` (present or absent) in a sentinel file before writing anything, and
  never hides if that file cannot be written. Turning the mode off, quitting (`prepareForTermination`)
  and the next launch after a crash (`recoverAfterCrash`) all restore exactly those values, removing
  keys that were absent, and delete the sentinel.
- **A saved macOS Dock layout keeps each tile's own dictionary.** `NativeDockTile.raw` is the tile
  as captured, re-written verbatim unless Onecast changed its kind, so applying a layout loses no key
  the model does not understand. Only pinned apps and spacers are saved; never folders, size,
  position or magnification.
- **A DockWidget is one object per instance.** The host calls the entry point once per dock item, so
  instance state can live in properties; per-instance settings live under
  `dockwidget.<instanceID>.<name>` and are deleted with the instance.
- **Third-party DockWidgets need consent; built-ins do not.** `dockWidgetsEnabled` confirms before it
  turns on and, like `docksEnabled`, never rides a backup or `settings.json`.
- **Built-in widgets share data sources through `DockWidgetServices`,** owned by `DockWidgetManager`
  and so by `AppCore`. Each source (clock, CPU and memory, network, battery, Now Playing, stock
  quotes) runs only while some tile leases it.
- **The dock never becomes key and is never registered with `ActivationPolicy`.** Anything that needs
  key — a menu, a folder popout, a widget popover — is a panel of its own.

## How it fits together

```
DockStore ──onChange──▶ DockCoordinator.applyEnabled()
                         ├─ DockPanelController.reconcile   one DockPanel per visible dock
                         ├─ NativeDockService.applyHiding   com.apple.dock + killall Dock
                         ├─ DockWindowObserver.setActive    minimized windows, previews, badges
                         ├─ DockWidgetManager               built-ins + compiled DockWidgets
                         └─ DockSwitchCoordinator           launcher rows, hotkeys, menu bar, URLs
```

| Piece | Holds |
| --- | --- |
| `Model/DockModels.swift`, `DockStore.swift` | the configuration and its store |
| `Model/DockGeometry.swift`, `DockSlots.swift`, `DockStripLayout.swift`, `DockPopupPlacement.swift` | pure frames, slot order, lens layout, popup placement |
| `Model/NativeDockPlist.swift`, `NativeDockHidingPlan.swift`, `NativeDockError.swift` | pure `persistent-apps` conversion and hiding decisions |
| `Model/DockURL.swift`, `DockEntryID.swift`, `DockBadges.swift`, `DockWidgetManifest.swift` | links, launcher ids, badge mapping, the widget manifest |
| `UI/DockCoordinator.swift` | every feature action |
| `UI/DockSwitchCoordinator.swift`, `UI/DockMenuBarMenu.swift`, `Intents/` | switching from hotkeys, launcher, menu bar, links and Focus |
| `UI/DockPanelController.swift`, `DockSurface*.swift`, `DockContainerView.swift`, `DockView.swift`, `DockTileViews.swift`, `DockFloating*.swift`, `DockMenus.swift`, `DockPopupViews.swift` | the dock windows and everything drawn in them |
| `Service/NativeDockService.swift` | reading, writing, hiding and watching the macOS Dock |
| `Service/DockWindowObserver.swift` and helpers | AX observers, ScreenCaptureKit previews, Dock badges |
| `Service/DockWidgetManager.swift`, `DockWidgetCatalog.swift` | the widget catalog, builds, instances and contexts |
| `Service/DockRunningAppsMonitor.swift`, `DockTrashMonitor.swift`, `DockItemActions.swift` | running apps, the Trash, what a click or drop does |
| `Widgets/` | the widget host views, the settings section, built-ins under `BuiltIn/` |
| `Settings/` | Settings › Docks |

## Modes and the macOS Dock

`NativeDockMode` is **macOS Dock only** (no custom docks; layouts still switch), **both** (the macOS
Dock untouched) or **custom docks as main**, where `NativeDockHiding` picks **reachable** (auto-hide,
revealed at its edge) or **hidden** (auto-hide behind a 1000-second reveal delay). Preferences are
read and written through `CFPreferences` on `com.apple.dock`, then the Dock restarts with
`killall Dock`, off-main and coalesced. Applying a layout first checks every app still resolves —
re-pointing a moved app by bundle ID, refusing with the missing names otherwise — and skips the write
entirely when the Dock already shows an equivalent layout. **Automatically save Dock changes** watches
`~/Library/Preferences` and saves the live Dock's pinned apps into the active layout, ignoring the
echo of Onecast's own writes.

## Switching

A dock shows one of its own layouts; a two-finger swipe across it or ⌘-scroll steps through them, as
does its menu. A **setup** names a macOS Dock layout and, per dock, whether it shows and which layout
— a dock it leaves out is left alone. Setups switch from a shortcut (`HotKeyAction.dockSetup`), a
launcher row, the menu bar's Docks menu, `onecast://dock/setup/<name-or-id>`, and the **Switch Dock**
Focus filter (System Settings › Focus › a Focus › Focus Filters › Onecast). Turning a Focus off
switches nothing back. `HotKeyAction.dockVisibility` shows or hides one dock. See
[launcher.md](launcher.md#docks) and [hotkeys.md](hotkeys.md).

## The dock surface

- **Placement.** One panel per visible dock, on its display (`NSScreen.displayKey`, else the menu-bar
  display) and edge, centred at its alignment; re-placed when displays change. A `.floating` dock sits
  at the system Dock's level, a `.desktop` one just above the desktop icons. Panels are `.transient`,
  so Mission Control hides them as it hides the real Dock. `reservedFrames` lists the docks that take
  space, which Onecast's own window commands and layouts leave clear
  ([window-management.md](window-management.md)).
- **The look.** A glass plate and a handle pill at its end (drag it along the edge to move the
  dock); every widget is a card inside it with Dockset's modest corner (`cardRadiusRatio`, about a
  sixth of the tile), and the plate's corner is the card's plus the padding, so the curves run parallel.
- **Anchoring, and a window that never resizes on hover.** The SwiftUI tree is aligned against the
  screen edge and centred along it. A magnifying dock's window always holds the lens's worst-case
  room (`lensRoom`, swept along the strip), because resizing a SwiftUI window as the pointer enters
  drew one stale frame: the flicker. Its clear margin passes clicks through to the apps behind.
- **Tiles carry no gestures.** `DockContainerView` owns every press, right click and scroll and
  hit-tests against `DockStripLayout`, the same pure layout the tiles are drawn from. A widget tile is
  the exception: left events pass through so its own buttons work, and the tile reports its tap.
- **The lens grows the strip evenly from its centre**, as the macOS Dock does, and the plate takes
  one width for the whole hover: the most the lens can ever add (`plateGrowth`, from the same sweep
  as `lensRoom`), eased in as the pointer arrives and out as it leaves. Its ends therefore never
  creep while the pointer moves. Tiles before the pointer keep to the plate's start and tiles after
  it to its end; the unused room is handed across three tiles at the pointer with a smoothstep, so
  a far tile never moves and no tile ever doubles back during a one-way sweep (pinned in
  `dock-strip-layout-test`). (Anchoring the lens to the pointer slid the whole bar; handing the room
  over within one tile darted icons sideways.) Icons and widgets magnify, every slot gaining at
  most one icon's growth; spacers and dividers keep their size. Each tile is laid out once at its
  peak size (a widget only while it grows, so its text stays sharp) and is scaled and moved by
  transforms, which, unlike frames, are never rounded to whole points: on a 1x display rounding
  made slow-moving icons flip back and forth by a point. While the lens is up, an invisible cover
  over everything it grew keeps the pointer on the dock. `DockLensDriver` eases the lens and the
  pointer toward their targets once per display frame on a `CADisplayLink`, idling once settled:
  mouse moves arrive unevenly and in pairs, and stacking a SwiftUI animation on each one shoved the
  icons back and forth.
- **Auto-hide slides the plate inside its window, then fits the window**, leaving a `handleThickness`
  strip, never a window parked off screen. Reveal is a global pointer monitor on the reveal zone,
  armed only while some dock hides; in a full-screen Space the pointer must rest there first. It is
  set per dock in Settings › Docks › Appearance, or from the dock's own right-click menu.
- **Yielding to the macOS Dock is detected, not assumed**: its window is looked for at the Dock level
  only while the pointer is near its edge.
- **Popups are panels**, one at a time; Escape, a click elsewhere and losing key close them.
- **A drag out removes, a drag within reorders, and Escape cancels.** Tiles drag as a private
  pasteboard type; dropped on another dock a tile moves there as itself (`transferItem`, one write),
  so a widget keeps its instance and settings. Files dropped on empty space are added,
  on an app open with it, on the Trash are trashed, on the AirDrop widget are sent.

## Minimized windows, previews and badges

`DockWindowObserver` runs only while a visible dock asks for minimized windows or badges, and only
with Accessibility. Minimized windows come from per-app `AXObserver`s seeded by one sweep; a window is
identified by its window-server ID through the private `_AXUIElementGetWindow`, the one private call
in the app, kept because no public API names a window. With Screen Recording, a focused window is
snapshotted every few seconds so a later minimize has a preview, cached downscaled on disk until the
window closes. Badges are read from the macOS Dock's own accessibility tree every few seconds, which
works while that Dock is hidden.

## DockWidgets

The author's guide — manifest, protocol, sizes, preferences, actions, lifecycle — is
[dockwidgets.md](../../custom_docs/dockwidgets.md). Built-ins implement the same `OnecastDockWidget`
protocol in-process:

| Group | Widgets |
| --- | --- |
| Time | Clock, World Clock, Focus Timer, Stopwatch, Countdown, Alarm, Time Progress |
| Productivity | Calendar, Reminders, Sticky Note, Shortcut, AirDrop |
| System | Now Playing (Spotify and Music over Apple Events), Battery, System Activity, Network Activity |
| Personal | Hydration, Weather (Open-Meteo), AI Usage (one service per tile: Codex limits and logs; Claude Code limits with its own keychain sign-in, never refreshed by Onecast, and logs; or GitHub Copilot quotas through the signed-in `gh`, which keeps no logs), Stock, Watchlist |

Networked widgets use private `.ephemeral` sessions with no URL cache. Business integrations (Stripe,
Paddle, Shopify) are deliberately left to third-party DockWidgets.

## Things that are not obvious

- **`~/.Trash` is protected.** Without Full Disk Access the Trash tile keeps its empty icon; dropping
  a file on it still moves it there.
- **A tile's label is not the `tooltip` modifier**, which the dock's window would clip.
- **Icons are `IconCache`'s 96-pixel bitmaps**; a tile above 96 points is upscaled.
- **While a dock scrolls, it does not magnify.**
- **A widget tile's click is replayed.** The container claims every left press so a widget can drag
  like any tile; a press that never leaves the slop is sent again, release posted first, to the
  widget's own SwiftUI view. A widget dragged off every dock is removed, like any tile, and its
  settings go with it (an API key typed into a widget is gone); Escape cancels the drag.
- **After a crash, launch restores then re-hides the macOS Dock**, so it restarts twice.
- **An app's dock icon can be replaced.** `DockAppReference.customIcon` is an image file or an SF
  Symbol. An image goes through `IconCache`'s `artwork` source at app-icon extent, so it matches real
  icons, whose artwork carries its own margin. A symbol is drawn as a card that fills the tile, like
  a widget's (`DockSymbolCard`): at app-icon extent it read as undersized beside the widgets. It is
  only cosmetic: matching a tile to its running app still goes by bundle ID and path. An image is
  kept by path, not copied, so moving the file leaves a dashed placeholder; its modification time is
  part of the cache key, so editing the file refreshes the tile. Only pinned apps take one.
- **A Finder that was quit opens a window on the first click.** Launched from nothing, Finder shows
  only the desktop and opens a window only when told to open again, so `AppLauncher.launch` sends that
  second open once a freshly launched Finder is up.
