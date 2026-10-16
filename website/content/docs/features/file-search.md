---
title: File search
description: Find files and folders from Onecast's own disk index, with a preview.
---

Search file and folder names across your disk, from Onecast's own index.

**Settings → File Search** holds the switch. It ships **off**. While it is off there is no command
and no index on disk.

Open it with the **Search Files** command, its own global shortcut, or the **Search Files** row under
"Use … with" at the bottom of any launcher search. That last one opens with your text already typed.

## Full Disk Access

File Search reads your disk directly to build a private index on this Mac, so it needs **Full Disk
Access**. Onecast cannot prompt for it: turn it on in **System Settings → Privacy & Security → Full
Disk Access**, or press <kbd>return</kbd> on the Search Files screen, which opens that pane. The
**Full Disk Access** row in **Settings → File Search** shows whether it is granted. Granting it starts
the build with no relaunch.

Hidden files and the insides of app bundles are indexed too, but rank last.

## The screen

With nothing typed, the list shows **Recent**: the newest files in your home folder and cloud drives.

Type and it becomes **Results**. Each row shows the file's icon and name. A folder also shows its
parent folder's name, dimmed, because half the folders on a developer's Mac are called `src`.

The right side previews the selected file: the file itself, then its name, location, type, size and
dates. Videos and audio can be played there. Nothing plays until you press play.

### Filtering by type

<kbd>⌘</kbd><kbd>P</kbd>, or the **All Types** button, narrows the search:

**All Types** · **Folders** · **Documents** · **Images** · **Audio** · **Videos** · **Archives**

The filter applies to the index's matches, so narrowing never hides a match. It resets each time you
open the palette.

## Actions

| Action                  | Shortcut                             |
| ----------------------- | ------------------------------------ |
| Open File / Open Folder | <kbd>return</kbd>                    |
| Show in Finder          | <kbd>⌘</kbd><kbd>return</kbd>        |
| Quick Look              | <kbd>⌘</kbd><kbd>Y</kbd>             |
| Copy File               | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Paste File to …         | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd> |
| Copy Name               | <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Copy Path               | <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Move to Trash           | <kbd>⌃</kbd><kbd>X</kbd>             |

- **Quick Look** opens a large preview inside the palette, and it plays media straight away.
  <kbd>esc</kbd> or **Close** puts it away.
- **Copy File** puts the file itself on the clipboard, ready to paste into Finder or Mail.
- **Paste File to …** pastes it into the app you opened the palette over.
- **Copy Name** and **Copy Path** keep the palette open, so you can copy several in a row.
- **Move to Trash** does not ask first. Things in the Trash can always come back.

Copies from here land in your [clipboard history](/docs/features/clipboard) like any other copy.

## The index

**Settings → File Search → Index** shows how many items are indexed and when the index was built, and
**Rebuild Index** crawls everything again. The first build runs in the background, with a running
item count in Settings and in the palette, and results appear when it finishes. It runs in a helper
process that exits when it is done, so Onecast's own memory stays small. Afterwards the index follows
changes on disk within a moment. Turning File Search off deletes the index.

## In the launcher

Turn on **Show in launcher**, under the File Search switch, to see files in launcher searches too.
It's **off** by default.

When your search has three or more characters, a **Files** section lists up to five matches. It sits
below the apps and commands, so <kbd>return</kbd> still opens the top result. Each row shows the
name, the folder it's in, and whether it's a file or a folder.

The rows have the same actions as this screen, except Quick Look. To see every match, choose the
**Search Files** row under "Use … with".

## Search scopes

**Settings → File Search → Search Scopes**, set to the whole disk by default.

Only what lies under a scope is indexed and searched. A folder inside another scope is folded into it,
and **an empty scope list searches nothing**. Changing the list rebuilds the index.

Scopes are saved with `~` shortened, so a backup still points somewhere sensible on another Mac.

## Ignore patterns

**Settings → File Search → Ignore Patterns**. A matching folder is skipped while indexing, with
everything in it. Three kinds:

| Pattern          | Checked against    | Example          |
| ---------------- | ------------------ | ---------------- |
| Plain word       | Any folder or name | `node_modules`   |
| With `*` `?` `[` | Any folder or name | `*.tmp`          |
| Containing `/`   | The whole path     | `**/[Cc]ache/**` |

Matching ignores case, and `*` also matches `/`, so a `**/…/**` pattern works as written. A path
starting with `~/` is taken from your home folder, and **Add Folder…** adds one for you.

The list only holds what you add. Six sensible rules are built in and always apply. Changing the list
rebuilds the index.

## How search works

All the words you type must be in the file name, in any order. `annual report` finds
"Report – annual 2025.pdf".

Results come from Onecast's own index, so a search takes a few milliseconds and is shown as you type.
Files in your home folder rank above system, hidden and app-bundle files with the same name. At most
**200** rows are shown.

## Messages you might see

| You see                          | It means                                        |
| -------------------------------- | ----------------------------------------------- |
| Full Disk Access required        | Press <kbd>return</kbd> to open the Privacy pane |
| Indexing your disk…              | The first build is running; results follow it   |
| Couldn’t build the file index    | Try **Rebuild Index** in Settings               |
| Type to search files and folders | Nothing recent in your scopes                   |
| No files found                   | The search finished with no match               |
| No images found                  | The same, with the Images filter on             |
