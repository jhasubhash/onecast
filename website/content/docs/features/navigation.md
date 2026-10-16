---
title: Navigation
description: Jump to any open window, or press any menu bar item, from the launcher.
---

Navigation adds three keyboard commands:

- **Switch Windows** lists every open window of every running app and brings the one you choose to
  the front.
- **Switch Windows Backwards** opens the same list and moves through it in reverse.
- **Search Menu Bar Items** lists every item in the frontmost app's menus and clicks the one you
  choose.

Turn it on in **Settings → Navigation → Enable navigation**. It's **off** by default. While it's off,
none of the commands appears in the launcher and their shortcuts do nothing.

All three need the [Accessibility permission](/docs/permissions). None needs Screen Recording.

Each command has a checkbox, a shortcut recorder and an alias field in **Settings → Navigation**.

## Switch Windows

The list starts with the app you used most recently, and each app's windows follow in their own
front-to-back order. **Minimized windows come last.** Type to filter by window title or app name.

<kbd>return</kbd> (**Switch to Window**) brings the window forward:

- A minimized window is restored first.
- A window on another Space pulls that Space forward.

If the app quit between opening the list and pressing <kbd>return</kbd>, Onecast tells you instead of
doing nothing.

The Switch Windows Backwards shortcut moves up the list instead, wrapping around to the last window.
Set it to <kbd>⌥</kbd><kbd>⇧</kbd><kbd>tab</kbd> and, while holding <kbd>⌥</kbd>, press
<kbd>tab</kbd> or <kbd>⇧</kbd><kbd>tab</kbd> to move either way before you release.

## Search Menu Bar Items

Open it over any app and every menu item appears as a row: the app's icon, the item's name, where it
lives (like `File → Export`), and its keyboard shortcut if it has one.

With an empty search, rows are grouped by top-level menu, like File, Edit and View. Type and the list
becomes one ranked **Results** list across all menus. <kbd>return</kbd> (**Activate Menu Item**) presses
it.

### Good to know

- **It works on the app that was in front when you opened it.** Switching apps afterwards does not
  change the target.
- **Only items you could click are listed.** Disabled items, separators and hidden items are left
  out.
- **Onecast never opens menus to read them.** Some apps build a submenu only when you open it, so
  those items may be missing. Opening menus behind your back would flash the app's UI every time.
- Very large menus are capped at 4,000 items, and reading stops after about a second.

### Settings

| Setting               | Default | What it does                                        |
| --------------------- | ------- | --------------------------------------------------- |
| Show Apple menu items | **Off** | Adds the Apple menu, which is the same in every app |
| Disabled Applications | Empty   | Apps whose menus Onecast will not read at all      |

An app on the Disabled Applications list is refused before its menus are read, not filtered
afterwards.

If there is nothing to search, you get a plain sentence instead of an empty list, like
**Finder has no menu bar to search** or **Menu search is turned off for 1Password**.
