---
title: Hotkeys
description: Recording global shortcuts, double-tap modifiers, and the Hyper key.
---

**Onecast ships with nothing bound.** Every global shortcut is one you record.

## What can have a shortcut

- The palette itself (**App Launcher**, in Settings → General)
- Every built-in command, except Open in Browser, Run Shell Command and Quit Onecast. See
  [Commands](/docs/launcher/commands).
- Every app, and every System Settings pane
- Every quicklink, custom command, custom Quick Action and extension command
- All 31 [system actions](/docs/launcher/system-actions)
- All 35 [window commands](/docs/features/window-management), and every
  [window layout](/docs/features/window-layouts)

Each shortcut is recorded on the item's row in its Settings pane, and shows as keycaps on its
launcher row.

A command that opens a screen is a toggle. Press its shortcut once to open the screen, and again to
close it.

## Recording one

The recorder is not a normal text field. Click it, then press the keys you want.

A small bubble above the field shows the prompt, then the modifiers you are holding, then a warning if
the shortcut is already taken, naming exactly what uses it.

Recording needs **no permission**. Only _using_ some kinds of shortcut does.

## Double-tap modifiers

Any shortcut can instead be a double tap of one lone <kbd>⌃</kbd>, <kbd>⌥</kbd>, <kbd>⇧</kbd> or
<kbd>⌘</kbd>.

The exact rules:

- A **tap** is a press of exactly one of those four keys, with nothing else held, no other key and no
  click, released within **250 ms**.
- A **double tap** is a second tap of the same key starting within **300 ms** of the first release.
- **It fires when you let go the second time, not when you press.** The key is already up when the
  action runs, and "double-tap and hold" does nothing on purpose.

<kbd>⇧</kbd> works as a double tap, even though <kbd>⇧</kbd> alone cannot be a normal shortcut. Caps
Lock cannot be used this way; that is what the Hyper key is for. Having Caps Lock _on_ does not get in
the way.

This needs [Accessibility](/docs/permissions), and **never asks for it on its own**. The shortcut is
saved anyway, the recorder shows a warning that opens System Settings, and the shortcut starts working
the moment you grant access.

Onecast only watches for double taps **while at least one shortcut uses one**, so if you never do,
it costs nothing.

## Hyper key

**Settings → General → Hyper Key** turns one physical key into <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd>,
or <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd> with **Include Shift** on.

You can choose **Caps Lock**, or the **Left** or **Right** side of **Control**, **Shift**,
**Option** or **Command**.

Function keys are not offered. Their media functions fire before Onecast can see them, and catching
them earlier would need Input Monitoring, which Onecast never asks for.

Shortcuts you already use with those modifiers work with Hyper right away.

### The ✦ symbol

**Any shortcut that includes all the Hyper modifiers shows as a single ✦.** So
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> shows as `✦G`, or `✦⇧G` when an extra modifier is
left over.

This is simply how it is written, not a setting. With no Hyper key set,
<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> shows as itself.

### Include Shift

Switching this **updates every saved shortcut**, so nothing breaks. If an update would clash with
another shortcut, that one is skipped and keeps its original keys.

The option is greyed out while Hyper Key is set to None.

### Quick Press

**Settings → General → Quick Press** decides what pressing Caps Lock on its own does while it is
your Hyper key: **Does Nothing** (default), **Trigger Caps Lock**, or **Trigger Escape**.

Escape is the favorite choice for Caps Lock users.

### Caps Lock details

While Caps Lock is your Hyper key, it is remapped at the hardware level on **every keyboard**,
including one you plug in later. Any remap another app made for a different key is kept.

The remap is removed when you pick another key or when Onecast quits, and it never survives a
restart. If Onecast is force quit or crashes, it stays until Onecast opens again, which removes it.
It is also paused while your Mac sleeps, while the screen is locked, so Caps Lock works in the
login password field, and while another user account is active.

If a keyboard ever loses the remap, one press there acts as plain Caps Lock. Onecast then remaps
that keyboard again and turns Caps Lock back off.

Hyper needs Accessibility. Onecast asks for it when you choose a key, keeps checking, and starts
working as soon as access is granted.

### Status and diagnostics

The **Status** row under the key shows a dot: green while Hyper works. Click **Diagnostics…** to see
what is running, which keyboards are remapped, and anything that conflicts. **Restart Hyper Key**
sets everything up again.

### Conflicts

- **Hyperkey** or **Superkey** running: they have their own Hyper key, so Onecast's stays off and
  says so. It starts again by itself when you quit them.
- **BetterTouchTool** running: listed in Diagnostics as a possible conflict, nothing more.
- **Karabiner-Elements** remapping the same key: shown in Diagnostics.
- **System Settings → Keyboard → Modifier Keys** remapping Caps Lock: this blocks Hyper.
  Diagnostics names the keyboard and links to the setting.

### Secure Input

Password fields, password managers and some terminals turn on macOS **Secure Input**, which hides
every key press from apps like Onecast. While it is on, Hyper cannot work, and pressing it shows a
message saying why. Diagnostics names the app most likely holding Secure Input.

With Caps Lock as your Hyper key, turn on **Secure Input Compatibility** to keep **Onecast's own**
Hyper shortcuts working there. Caps Lock then acts as **Right Control**, so while it is on, the Right
Control key also works as Hyper and its own shortcuts are reserved. Inside Secure Input, **Right
Control** plus a shortcut's key runs that Hyper shortcut. Left Control never triggers Hyper;
existing Onecast Control shortcuts still work with Left Control. The Control combinations used by
Hyper are reserved while Secure Input lasts. Other apps' Hyper shortcuts still do not work there.

## Hidden, switched off, and turned off

**Hiding a row does not turn off its shortcut.** Unticking a row's checkbox, or
<kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> in the launcher, only changes what search shows.

**A section's switch does turn off its shortcuts.** **Enable Applications**, **Enable System
Settings**, **Enable System Actions** and **Enable Commands** each stop every shortcut in their pane.

**Turning a feature off turns off its shortcuts.** File Search, Notes, AI, Quick Actions, Navigation,
Calendar, window commands, quicklinks, custom commands and extensions all check their switch before
doing anything. Turn the feature back on and your shortcuts work again.

A [system action's confirmation](/docs/launcher/system-actions#confirmation) comes up for its shortcut
exactly as it does in the palette.

## Keeping them

Shortcuts are included in [backups](/docs/reference/backup), except for custom Quick Actions.

Shortcuts for things you deleted while Onecast was not running are cleaned up the next time it
starts.
