# Shelf

A floating drop zone in the spirit of Dropover. Shake the pointer from side to side while dragging
anything — files from Finder, an image from a browser, a link, a run of text — and a shelf opens under
the pointer to drop it on. Gather things from several places, then drag them out to wherever they are
going. `Show Shelf` opens and closes it from the launcher, so it takes an alias and a global shortcut
like any other command.

## Invariants

- **Files move, both ways.** A file dropped from the same volume moves into the shelf's holding
  folder (`~/Library/Caches/<bundle id>/Shelf/<uuid>/`), and dragging it out offers `.move` first, so
  Finder moves it on. Holding ⌥ while dropping leaves the file where it is and the shelf only points at
  it. A file on another volume is never moved in — that would be a copy across disks on the main
  thread — so it is held by reference.
- **Letting go puts it back.** Closing the shelf, Clear Shelf and a row's remove button move every held
  file back to the path it came from (`ShelfReturn` numbers it beside anything now in that spot; a
  folder that no longer exists sends it to Downloads). Nothing the shelf holds is ever deleted except
  what it made itself: dropped image pixels and promised files have no origin.
- **The origin lives beside the file, not on it.** `<uuid>.origin` sits next to the holding folder, so
  nothing of the shelf's travels with a file Finder moves out. A launch after a crash releases
  whatever the last one still held.
- **A moved-out file leaves the shelf.** When the destination reports a move (or the Trash takes it),
  the dragged rows leave at once. The shelf does not wait for the file to disappear, because Finder
  moves asynchronously. Their holding folders are tidied once Finder finishes. A copy (to Slack, Mail,
  a browser, or another disk) leaves the row in place.
- **A shake needs a real drag.** `DragShakeMonitor` only feeds `ShakeDetector` while the drag
  pasteboard has changed since mouse-down, so moving a window or selecting text never opens the shelf.
  A shake is three reversals of at least 30 pt within 0.7 s, and fires once per drag. The shake opens
  the shelf without taking key, so the source app's drag is undisturbed.

## How it is put together

| Layer | Pieces |
|---|---|
| Model | `ShelfItem` (file, link or text, plus a file's origin), `ShelfGroup` (one drop), `ShelfStack` (grouping, dedupe and summary), `ShelfReturn` (where a file goes back to), `ShelfSelection`, `ShakeDetector` |
| Service | `ShelfIntake` (reads a drop: files, file promises, image data, links, text; holds and releases files), `DragShakeMonitor` (global and local left-drag monitors) |
| UI | `ShelfCoordinator` (lazy on `AppCore`), `ShelfPanel` and `ShelfDropView` (non-activating floating panel on every desktop), `ShelfDragSource` (AppKit drag source for one row or the whole stack), `ShelfView` |
| Settings | `ShelfSettingsView`: Enable Shelf, Shake to Open, and the Shelf commands |

## Groups

Each drop is its own group: drag two files in and the shelf shows one stack of two; drag three more and
a second stack appears below it. Dragging a group drags everything in it at once. A group of more than
one opens (chevron, double-click, or Show Items in its right-click menu) to list its items, and each of
those drags out on its own; ‹ or Esc steps back to every group. A promised file that arrives after its
drop joins that drop's group rather than starting one of its own. When a group's last item leaves, the
group goes, and an open group that empties steps back out.

Rows select like Finder's list: click picks one, ⌘-click adds or drops a row, ⇧-click takes the run
from the last pick, ⌘A takes every row on show, and ⌫ removes the picks (putting their files back).
Dragging a picked row drags every pick, so a few files leave a group while the rest stay; a plain press
on a pick keeps the selection for that drag and only a click without one narrows it. Esc drops the
selection first. The pure rules are `ShelfSelection`. Hover labels draw in their own panel
(`ShelfTooltip`), since the shelf's window would clip them.

The header's stacked icons drag every item on the shelf. Right-click a group or item for Open (or Show
Items), Show in Finder, Copy, Share… and Remove from Shelf; the ⋯ menu copies, reveals, shares or clears
everything. Esc closes the shelf when no group is open.

## Tests

`Tests/shelf-test.swift` covers the groups (one per drop, late deliveries, dedupe, removal, titles), selection (click, ⌘, ⇧, a drag from a pick), the summary, the return destination
and the shake detector (a shake, jitter, slow sweeps, firing once).
