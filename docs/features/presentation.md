# Presentation Mode

One click before a screen share: every other app is put away, the front app's window is sized for
the people watching, and the display can switch to a resolution whose text reads at their end.
Ending it puts everything back. Started from the Presentation DockWidget, the button in Settings ›
Presentation, or three launcher commands, each bindable to a shortcut: **Start Presentation**,
**Stop Presentation** and **Toggle Presentation Mode**. They run the same coordinator calls as the
widget's button, so the widget follows; Start while presenting and Stop while idle only say so.

Ships **on**: it is inert until started, and starting it is always an explicit gesture.

## Invariants

- **Every effect is recorded and undone, and only what Onecast did is undone.** `PresentationSession`
  keeps the apps it hid, the windows it minimized, the windows it moved (with their first frame)
  and the windows it put in full screen. Ending unhides only the apps it hid, unminimizes only its
  own minimizes, and restores frames only when **Restore windows afterwards** is on.
- **A resolution change lasts only as long as Onecast runs.** It goes through
  `CGDisplaySetDisplayMode`, which macOS reverts to the user's own mode when the calling process
  exits, so a quit or a crash mid-presentation cannot strand a display at the presenting size.
  Nothing about it is persisted.
- **A stored resolution names a size and a scale, never a refresh rate** (`1920x1080@2x`): another
  cable or dock changes the rate, and the choice must still match. It resolves to that display's
  fastest matching mode (`PresentationResolutionPolicy.index`).
- **Choices are per display**, keyed by `NSScreen.displayKey`, so the laptop at work and the monitor
  at home each remember their own. Only the display the presentation runs on is switched.
- **Apps to leave alone are never touched**: not presented, hidden, minimized or resized. Meeting
  apps are on it by default (Teams, Zoom, Webex, FaceTime), because hiding one hides the call's own
  controls and sharing toolbar.
- **Window writes go through `AXWindowAccess.write`**, the window-management feature's one
  size → position → size sequence, and frames are computed in AX space from
  `AXScreens.usableFrame`, so Onecast's own docks are never covered.
- **`Model/` stays pure**: `PresentationFrameEngine`, `PresentationResolutionPolicy`,
  `PresentationDisplayMode` and the option enums compile into `Tests/presentation-test.swift`.

## How it fits together

```
PresentationCoordinator (UI/)     phase, start/stop/refit, app-activation observer, HUDs
 ├─ PresentationDisplayAccess     CGDisplay modes: list, switch, wait for AppKit to settle
 └─ PresentationSession           one presentation's AX/NSRunningApplication effects + undo
Model/                            options, display mode, resolution policy, frame engine
Settings/PresentationSettingsView Settings › Presentation
Docks/Widgets/BuiltIn/Productivity/Presentation*  the DockWidget
```

## Starting

1. The **target** is the frontmost regular app that is not Onecast and not on the leave-alone list.
   With none (Settings in front, or the meeting app), nothing is presented yet; the next app
   brought forward is.
2. The **presentation display** is the one holding most of the target's window, else the one under
   the pointer.
3. The **start shortcut** (an Apple Shortcut by name, e.g. one that turns on Do Not Disturb, since
   macOS offers no API for Focus) runs, unawaited.
4. If that display has a stored resolution different from its current mode, it switches, then waits
   for AppKit to report the new size plus a short grace for the Dock and menu bar.
5. Other apps are put away per **Other apps** — hidden (default), minimized, or left — on the
   windows two choices reach (`PresentationScopePolicy.reach`), **Displays** and **Spaces**, each
   *Active* or *All* (both *All* by default):
   - *All / All*: every candidate app.
   - Otherwise, apps with a window in the window list that passes both: on the presentation display
     (its centre inside it) when Displays is *Active*, and on screen now when Spaces is *Active*.
     *Active / Active* is the Space the shared display shows now, and nothing else. A minimize takes
     only the reached windows, matched to their AX elements by frame.
   - Spaces *All* with a minimize also hides the app: AX hands an app only the windows of the Spaces
     on screen, so hiding is the only reach into the others.
   A hide is always the whole app, on every Space and display, since that is what hiding is.
6. The target's window is sized per **Presented window**: centred with a margin (default 10% of the
   usable area on each side), filling the usable area, macOS full screen (placed on the presentation
   display first), or left as it is. A window already in full screen is left alone.

## While presenting

An app brought forward follows **When you switch apps**: *replace* presents it and puts the previous
one away (minimized when other apps are minimized, hidden otherwise, even if other apps are left
alone); *stack* presents it on top; *ignore* leaves it. A just-launched app's window is waited for
(15 × 200 ms). It is moved to the presentation display. Unplugging that display ends the
presentation.

**A Space switch is not an app switch.** Moving to another Space makes macOS activate whatever app
was in front there; presenting it would hide the presented app, and coming back would show the
wrong one. An activation is weighed after 300 ms: if a Space switch landed within 600 ms of it,
either side (`activeSpaceDidChangeNotification` stamps the time; the two arrive in either order), it
is not presented. Otherwise it is presented only while the presented app still has a window on
screen, that is, while you are on the presentation's Space.

**Activating a hidden app unhides it**, so with Spaces *All* the app a Space switch
brings forward is hidden again (`PresentationSession.hideAgain`), keeping other Spaces clear. That
is checked on the activation and again 300 ms after every Space switch, since an app already in
front (Finder, once it took over from the apps it replaced) posts no activation when its Space
returns yet is still unhidden. Only an app this presentation hid is re-hidden.

**While Presenting** settings: *Hide custom docks* (off by default) takes Onecast's docks off screen
through `DockCoordinator.setHiddenForPresentation`, which never touches their configuration;
*Show in the menu bar* (on) inserts a menu-bar item only while presenting: a static recording glyph
whose menu shows the app and elapsed time, Stop Presentation, Re-fit Window and Settings (dragging it
out turns the setting off). The label never ticks: a `TimelineView` in a `MenuBarExtra` label kept
SwiftUI re-setting the status button's image and hung launch. *Keep the display awake* (on) holds a
`ProcessInfo` activity with `.idleDisplaySleepDisabled` until the end.

## Ending

Full screen is left first and given time to animate out, then the display's own mode comes back
(and settles), then frames are restored, minimized windows return and hidden apps are unhidden.
The **end shortcut** runs last. Quitting mid-presentation (`prepareForTermination`) restores the mode
and windows without waiting and skips the end shortcut.

## The DockWidget

`builtin.presentation`, in the Productivity group; it reads `AppCore.shared.presentationCoordinator`.

| Size | Shows | A click |
| --- | --- | --- |
| Compact (1 tile) | state (Present / Live) and the elapsed time | opens the detail popover |
| Wide (2 tiles) | the same, plus a start/stop button | the button toggles; elsewhere opens the popover |
| Expanded (4 tiles) | the same, plus the presented app, the resolution in use and the window plan, and a re-fit button | as wide |

The popover shows the presented app, display, resolution and elapsed time, start/end, **Re-fit
Window**, segmented pickers for the window size and margin (a change while presenting re-fits at
once) and a link to Settings › Presentation. The clock ticks per second only while presenting.

## Things that are not obvious

- **`NSRunningApplication.hide()` and `unhide()` answer `false` even when they work** (macOS 26), so
  a hide is recorded as requested, never by its return value; trusting it left every app hidden.
- **Tile buttons are quiet `controlSurface` circles** like the Calendar tile's call button; only
  *stop* is tinted, in red. Their tooltips draw in the dock's label panel (see docks.md).
- **Its HUDs draw over the dock** because `HUDPanel` sits at `.notice`, one level above the custom
  docks; earlier it sat at the palette's level, under them.
- **`kCGDisplayShowDuplicateLowResolutionModes` is not its own name.** Its value is
  `"kCGDisplayResolution"`; a string key spelled like the constant silently drops every HiDPI mode,
  leaving only the blurry 1x list. Use the constant.
- **A smaller HiDPI size is what makes text bigger for viewers.** A screen share captures pixels, then
  scales them to the stream; "looks like 1920 × 1080" on a 4K panel doubles every glyph relative to
  the frame. The 1x modes are listed (as *low resolution*) but rarely what you want.
- **Every preference is backup-excluded**: they are tuned to this Mac's displays and meeting setup.
  All but the per-display resolutions ride `settings.json` under `presentation.*`.
