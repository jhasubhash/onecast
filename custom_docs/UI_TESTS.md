# Driven UI verification

No UI test target exists — prove a change works: build, install, drive the app from the keyboard,
capture the panel, judge the pixels, instrument the view tree when they disagree.

Run for any new feature, palette screen, plugin, Raycast extension, or a surface's key/chrome/list
change. [testing.md](../docs/testing.md) owns the harnesses and manual sweep; this file covers what
a human would skip.

§7's register is the point: every bug that survived review, with symptom, cause, and the check that
would have caught it.

## 1. Prerequisites, once

- **Debug channel** only (`Onecast Dev.app`, `com.onecast.app.dev`) — the driver types into
  whatever holds focus.
- `osascript`'s process needs **Accessibility**, or key codes are silently swallowed.
- Palette hotkey starts unbound:

  ```sh
  defaults read com.onecast.app.dev | grep hotkey.togglePalette
  # {"combo":{"_0":{"carbonKeyCode":49,"carbonModifiers":256}}}  → ⌘Space
  ```

  `carbonKeyCode` = virtual key (49 = Space); `carbonModifiers` = Carbon mask (256 = ⌘, 512 = ⇧,
  2048 = ⌥, 4096 = ⌃).

## 2. Build, install, restart

| What changed | Command | Restart |
| --- | --- | --- |
| The app | the Debug `xcodebuild` line in [CUSTOM.md](CUSTOM.md) | yes |
| A native plugin | copy `manifest.json` + `.swift` into `…/plugins/<name>/` (the app compiles it) | leave & reopen the plugin, or restart |
| A Raycast extension | `npm run ship` (build + `install.sh`) | rescan in Settings, or restart |

Two traps: a `OnecastPluginKit` signature change (even a defaulted init param) invalidates every
cached plugin build — the app rebuilds each against the new framework on the next scan, but a plugin
already running keeps its old mapped image, so `pkill` and relaunch to be sure. Closing the palette
alone leaves the loaded dylib mapped.

```sh
pkill -f "Onecast Dev.app/Contents/MacOS"; sleep 2
open -a "$PWD/build/DerivedData/Build/Products/Debug/Onecast Dev.app"; sleep 6
```

## 3. Drive the real keyboard

One script, **run as a background job** — a foreground driver dies mid-run, leaving junk state.

```sh
cat > /tmp/drive.sh <<'EOF'
#!/bin/bash
k() { osascript -e "tell application \"System Events\" to key code $1"; }
t() { osascript -e "tell application \"System Events\" to keystroke \"$1\""; }
pkill -f "Onecast Dev.app/Contents/MacOS"; sleep 2
open -a "$HOME/Developer/onecast/build/DerivedData/Build/Products/Debug/Onecast Dev.app"
sleep 6
osascript -e 'tell application "System Events" to key code 49 using {command down}'; sleep 2
t "stock quotes"; sleep 1.5     # host launcher query
k 36; sleep 2.5                 # Return — open the surface
t "netfl"; sleep 3              # the surface's own field; wait for the network
k 51; sleep 3                   # ⌫ — the edit that re-runs the search
k 125; sleep 0.8                # ↓
EOF
bash /tmp/drive.sh
```

| Key | Code | Key | Code |
| --- | --- | --- | --- |
| Return | 36 | ↓ | 125 |
| Escape | 53 | ↑ | 126 |
| Delete (⌫) | 51 | ← | 123 |
| Space | 49 | → | 124 |

Timing: ≥ 2 s after the palette (early keys land in the previous app, or scramble); ~3 s past a
network-populated list before keys register, or ↓ resets selection; one screenshot per state,
in-script.

## 4. Capture the panel, not the screen

Ask the window its own rect and capture that — `screencapture -R` and the accessibility API's
`position`/`size` both use points:

```sh
osascript -e 'tell application "System Events" to tell process "Onecast Dev" \
  to get {position, size} of windows'
# 1844, 416, 750, 475
screencapture -x -R1844,416,750,475 /tmp/panel.png
```

Then **look at the image** — a vision-model "is this row highlighted?" isn't evidence; one session
called a hovered row selected and an accented row unhighlighted in the same run. Full-screen
`screencapture -x` downscaled is where subtle washes vanish.

## 5. When the pixels disagree with the model

Instrument, don't guess: append to a file from inside the view (`print` is invisible in a released
dylib under a GUI app):

```swift
private func debugLog(_ line: String) {                       // TEMPORARY
    guard let debug = FileHandle(forWritingAtPath: "/tmp/tcdebug.log") else { return }
    debug.seekToEndOfFile()
    debug.write(Data((line + "\n").utf8))
    try? debug.close()
}
```

`: > /tmp/tcdebug.log` first (handle needs an existing file). Log in order until one contradicts
the rest:

1. **Key path** — did the event reach the handler, with what modifiers.
2. **Model** — state the handler wrote (`selection`, `query`, counts).
3. **Render pass** — from `body` via `let _ = debugLog(…)`: derived values rendered with, including
   the collection itself, not just its count.
4. **Per-item state** — `row 3 NFLX.TO selected=false`, one line per row.
5. **Tree marker** — `@State private var treeID = UUID().uuidString.prefix(4)`: detached copy vs.
   unrepainted rows.
6. **Network** — status/byte count per attempt; a silent `try?` turns a 429 into an empty screen.

Strip every line before finishing:

```sh
grep -rn "FileHandle\|debugLog\|treeID\|/tmp/" Sources/ Onecast/ OnecastPluginKit/
```

## 6. What to check, per surface

**Every surface**

- Footer chips match reality, **hidden when their key is inert**.
- Escape unwinds one step at a time: query → stack → leave. No skipped levels.
- ⌫ edits text while the field is non-empty; backs out only once empty.
- Selection unmistakable from hover: accent wash + leading bar vs. faint grey — two percent apart
  reads as "the keys do nothing".
- Arrow keys move selection **and** scroll it into view, at both list ends.
- Nothing else on screen moves when selection does — a nested scroller is the usual culprit.

**A list whose data changes** (search-as-you-type, filtered watchlist)

- Edit the query mid-string (type, ⌫); rows themselves must change, not just the count —
  highest-yield check here.
- Selection lands on a row actually drawn post-change.
- Empty and error states render, both offer a way out.

**Anything rendered from the network**

- Run once with cache cleared (`defaults delete com.onecast.app.dev <key>`) — looking right only
  via caching is unverified.
- Every row populated, not most — one placeholder in five is a dropped request.
- Check what the code *asks for*, not just what it draws: an unordered/truncated request list fails
  silently, indistinguishable from a network error.

**A native plugin surface** — also check [plugins.md](plugins.md)'s keyboard contract: ⌘K
opens/runs a row, back chevron matches Escape, content clears the footer
(`.contentMargins(.bottom, …)`).

**A Raycast extension** — failing path too: non-zero exit, empty result, login-shell dependency
(`TERM=dumb` below).

## 7. Register of bugs that shipped past a review

Append to this.

### Half the watchlist had no price — 2026-09

**Symptom.** Dash, bare ticker instead of price/name on some cards, inconsistent across launches.
**Cause.** `Array(Set(favourites + recent)).prefix(12)` used an **unordered** set — favourites past
the cap dropped — and fired twelve per-symbol requests at once; a bare `try?` swallowed Yahoo's
`429`s into `nil`.
**Fix.** Favourites ordered first, one crumb-gated batch call per symbol
(`v7/finance/quote?symbols=…`), retries on 429/5xx, paced fallback, last-known quotes cached.
**Check.** §6 network check — clear cache, count rows.

### A vertical scroller chased an id inside a horizontal strip — 2026-09

**Symptom.** ← / → between favourite cards scrolled the page up slightly each press.
**Cause.** Watchlist's outer `ScrollViewReader` called `proxy.scrollTo(selIndex)` on every
selection change; ids `0..<favRefs.count` belong to the nested horizontal strip, so it centred a
card that hadn't moved vertically.
**Fix.** Each reader owns its range: vertical bails unless `selIndex >= favRefs.count`, horizontal
unless `selIndex < favRefs.count`.
**Check.** Step the horizontal axis, compare captures — elements must share a pixel row.

### SwiftUI identity conflict freezes a list — 2026-09

**Symptom.** ↑/↓ "stopped working" in a search list, only after editing the query.
**Cause.** `ForEach(Array(results.enumerated()), id: \.element.id)` keyed rows by symbol; each row
also carried `.id(index)` — two identities. Re-search changed the array, not the indices: SwiftUI
reused rendered rows, so selection walked a row never drawn while the list showed a stale symbol.
**Fix.** Key positionally: `ForEach(Array(results.enumerated()), id: \.offset)`.
**Check.** §6 "a list whose data changes" — type, backspace, arrow.

### Selection indistinguishable from hover — 2026-09

**Symptom.** Reported as "arrow keys don't navigate"; the keys were fine.
**Cause.** Selected drew `Color.primary.opacity(0.10)`, hover `0.06` — near-identical, neither read
as "here".
**Fix.** Accent wash + 3 pt leading bar for selection; hover stays faint grey.
**Check.** Mouse over the list *and* press ↓ — highlights must be tellable apart.

### A footer chip for a key that does nothing — 2026-09

**Symptom.** "Open ⏎" shown on a detail view where Return was inert.
**Cause.** `primaryActionLabel` was computed from the root list's state, not the view on top.
**Fix.** Derive the label from the current view (`navigator.canPop ? "" : "Open"`); `""` hides it.
**Check.** Walk every view, read the footer on each.

### The host stole a bare backspace from a plugin — 2026-09

**Symptom.** Deleting a character in a plugin's search field threw the user back to the launcher.
**Cause.** `PaletteWindowController.onBareBackspace` treats ⌫ as Escape's back step once *its*
query is empty — a surface's query isn't the host's.
**Fix.** A plugin surface owns the key; the host leaves it alone ([plugins.md](plugins.md)).
**Check.** Type in a surface's own field, then ⌫.

### Escape skipped a whole view — 2026-09

**Symptom.** Escape from search results left the plugin instead of returning to its list.
**Cause.** The scaffold went straight from `pop()` to `pluginExit()`, with no way for a surface to
consume Escape first.
**Fix.** `PluginScaffold(escape:)`, offered before pop and exit.
**Check.** Escape from the deepest state, count the steps back out.

### A stale dylib answering the keys — 2026-09

**Symptom.** A fix "did not take" after a rebuild.
**Cause.** Plugin dylib loads at launch — reinstalling under a running app changes nothing.
**Fix.** `pkill` and relaunch as part of the driver script, every run.
**Check.** Your driver restarts the app before typing anything.

### `TERM=dumb` noise swallowed a real error — 2026-09

**Symptom.** An extension showed `[ERROR] - (starship::print): Under a 'dumb' terminal` instead of
its own failure.
**Cause.** Shelling through an *interactive* login shell (`zsh -ilc`) sources `~/.zshrc`, whose
prompt framework writes stderr under `TERM=dumb`; the real message on stdout was discarded.
**Fix.** `zsh -lc` with `TERM=xterm-256color`, show stdout *and* stderr, strip prompt chatter.
**Check.** Run the command through the same shell it uses, read both streams.

### ⇧↵ sent instead of breaking a line in the AI composer — 2026-09

**Symptom.** In the floating AI bar, ⇧↵ sent the message like a bare ↵ instead of inserting a
newline; the composer also shared the launcher's single-line field.
**Cause.** The palette's container `onKeyPress(.return)` runs ahead of a focused `TextField`'s own
`.onKeyPress`, so the field-level ⇧↵ handler never fired and Return fell through to the send guard.
**Fix.** A dedicated `aiComposerField` (vertical axis, own font and growth), with ⇧↵ handled in the
container — `PalettePanel.insertIntoField("\n")` — before that guard.
**Check.** ⇧↵ in the AI bar adds a line; plain ↵ sends; the launcher field stays single-line.

### A transparent SVG fill rendered as a solid block — 2026-09

**Symptom.** An extension icon drawing a `fill="transparent"` shape came out as an opaque block
instead of empty.
**Cause.** `ExtensionIconCache.resolvingPaletteNames` rewrote only `raycast-*` colour names and
bailed otherwise, so `transparent` reached the SVG renderer — which draws it solid, not clear.
**Fix.** Always run the rewrite, and map a `fill`/`stroke` of `transparent` to `none` (#970).
**Check.** `ext-icon-test` rasterizes a transparent-filled rect at 96pt and asserts no ink.

### Scheduler notifications fired onto a secondary display — 2026-09

**Symptom.** A scheduled task's notification card appeared on the external monitor, not the
menu-bar display.
**Cause.** `NotificationPresenter` was built with `screen: { NSScreen.main }`; for an accessory app
that is the display of the last key window, not the primary one.
**Fix.** `NSScreen.primary` (`Platform/ScreenTarget.swift`), the same target the palette uses.
**Check.** With two displays, seed a task due in 20 s, then read its panel's bounds from
`CGWindowListCopyWindowInfo` — the origin must fall inside the display at the global origin.

### An all-spaces pop-out flashed over apps on every space switch — 2026-09

**Symptom.** A plugin pop-out kept on all spaces as a desktop widget jumped in front of every window
on the space just switched to, then sank behind them a moment later.
**Cause.** WindowServer draws a `.canJoinAllSpaces` window at `.normal` level above the arriving
space's windows until it re-sorts; `.stationary` changes nothing, only the level does.
**Fix.** ⌘K **Pin to Desktop** puts the window at desktop-icon level + 1, behind every app window.
**Check.** `screencapture` in a loop (~100 ms a frame) across a `⌃→`/`⌃←` switch onto a space whose
window covers the pop-out; no frame after arrival may show it.

### Every alias field wore the Siri orb — 2026-09

**Symptom.** A round Siri/Writing Tools badge floated at the leading edge of the first **Add Alias**
field in a Settings pane, over the command's name.
**Cause.** The alias field became an `NSTextView`, and macOS 26 attaches its Writing Tools orb to
every editable text view; a SwiftUI `TextField` never got one.
**Fix.** `writingToolsBehavior = .none` on the alias editor.
**Check.** Open a pane with commands and look at the alias column; hit-test the spot through AX — a
`button` described "Siri Waveform Orb" is the regression.

### A second ⌘F left the Settings search unfocused — 2026-09

**Symptom.** After arrowing into Settings search results, ⌘F did nothing; typing went to the list.
**Cause.** The shortcut set `.searchable(isPresented:)` to `true`, which it already was — a no-op
that moves no focus.
**Fix.** `.searchFocused($searchFocused)`, and ⌘F sets that focus directly.
**Check.** Search, ↓ into the results, ⌘F, ⌘A, type — the field must take the new query.

### A chat reply selected one block at a time — 2026-09

**Symptom.** A drag in an AI reply stopped at the paragraph or list item it began in; two bullets
could not be selected together, and tables never joined a selection.
**Cause.** Each markdown block was its own SwiftUI `Text`, and `.textSelection` never crosses views.
**Fix.** One TextKit 1 `MarkdownTextView` per reply (docs/features/ai.md). It takes focus only while
a click tracks, then returns it: accepting focus at other times let AppKit hand it a reply, which
stranded typing and ⎋ in read-only text.
**Check.** Drag from a paragraph through a list into a table; type (it must land in the composer);
⌘C with an empty composer, then right-click → Copy. Both must paste one line per paragraph or item,
`•`/`1.` markers, tab-separated cells, no blank lines. ⌘A in the composer then ⌘C copies the draft.

### AI chat windows never reopened after a quit — 2026-09

**Symptom.** A pop-out left open was gone on the next launch, though the code saved open windows.
**Cause.** Termination closed every window, and each close saved the list, so it was empty by exit.
**Fix.** `closeAllForQuit` closes without saving; closing a window by hand still forgets it.
**Check.** Open an AI Chat window, quit with ⌘Q, relaunch: it reopens on the same chat, unfocused.

### A default-scope chat window listed no chats — 2026-09

**Symptom.** The default chat's window opened empty, and one restored at launch opened a fresh chat.
**Cause.** Its store is born scoped to the default chat, so `setScope(nil)` returned before loading.
**Fix.** The window loads its store when it is made. Its typing also lands in the composer: AppKit
would give first responder to the sidebar's search, so the split view focuses the composer itself.
**Check.** ⌘J from the bar: the sidebar lists the day's chats, and typing at once fills the composer.

### Thinking shown for a slow network, and lost on reopen — 2026-09

**Symptom.** "Thinking…" and an open Reasoning fold appeared whenever a reply paused, then flickered
shut; all thinking sat above the whole reply, and none of it came back when the chat was reopened.
**Cause.** A stall timer read 2 quiet seconds as thinking, the fold followed that flag, and reasoning
was one unsaved string per message.
**Fix.** Only a route's own `.thinking`/`.reasoning` events count; thinking is timed blocks at the
point it happened, stored in `message_thinking`.
**Check.** On a reasoning route, a live block streams open, then folds to "Thought for Ns" when the
answer starts; thinking mid-answer gets its own block; the chat reopens after a relaunch with both.

### A low AI bar's history ran off-screen, and window shortcuts missed — 2026-09

**Symptom.** ⌘Y in a bar docked low opened history growing down past the screen's bottom, and its
back step became the full-window chat. In the AI Chat window ⌘Y did nothing and ⌘, opened General.
**Cause.** `openScreen` dropped the bar flavor on any mode but `.ai`, so history took the launcher's
placement. The window's key monitor had no ⌘Y or ⌘,, so the app menu's plain Settings… answered.
**Fix.** `aiBar` spans `.ai` and `.aiHistory`, ⌘Y toggles; re-entering `.ai` re-seats focus in its
own field. The window's ⌘Y toggles the sidebar and its ⌘, opens the AI pane.
**Check.** Bar docked at the bottom: ⌘Y four times — history grows up, the bottom edge never moves,
and each press lands. In a window: ⌘Y hides and shows the sidebar; ⌘, opens Settings on AI.

### The bar's ⌘, opened General, and a pop-out sank behind the last app — 2026-09

**Symptom.** ⌘, from the floating bar still opened Settings on General; ⌘J opened the chat window
behind whatever app had been in front.
**Cause.** AppKit offers a ⌘ chord to the key window's `performKeyEquivalent` and the main menu
before `sendEvent`, so the menu's plain Settings… took ⌘, first. `popOut` raised the window and
then hid the palette with focus restored to the previous app.
**Fix.** `PalettePanel.performKeyEquivalent` gives ⌘, to the palette's own handler; `popOut` hides
the palette with `restoreFocus: false`.
**Check.** With another app in front, summon the bar: ⌘, opens Settings on AI; ⌘J leaves the chat
window frontmost and key.

## 8. Before you call a UI change done

- Driver script ran end to end against a freshly restarted Debug build.
- One captured panel image per changed state, viewed rather than asked about.
- §6 checks pass, including type-then-backspace.
- Network-backed surfaces seen once with cache cleared.
- Every temporary log line gone, per the §5 grep.
- New failure modes go into §7 — same commit.
