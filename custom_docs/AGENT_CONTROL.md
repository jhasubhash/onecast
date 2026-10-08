# Agent control

A Debug-only channel that lets a coding agent drive Onecast and read its state as data: open a
screen, type, press keys, wait for a condition, and get back the palette's state and every window's
accessibility tree, in milliseconds rather than the seconds an `osascript` and screenshot loop costs.
The plan it came from is [agentic_investigation.md](../agentic_investigation.md); the manual,
keyboard-driven recipe it speeds up is [UI_TESTS.md](UI_TESTS.md).

## Invariants

- **Debug only.** Every file under `Features/AgentControl/Service/` and `UI/`, and its wiring in
  `AppCore`, sits inside `#if DEBUG`. A Release build has no listener. `Model/` is pure data with no
  effect of its own, so it compiles everywhere and the harness can reach it.
- **Loopback, authenticated, per launch.** `AgentControlServer` binds `127.0.0.1` on a
  kernel-assigned port and writes `{port, token, pid}` to
  `~/Library/Application Support/<bundle id>/agent-control.json`, mode `0600`. Every request carries
  `Authorization: Bearer <token>`; the token is new on every launch, and the file is removed on quit.
- **Actions go through the coordinators a user reaches.** `show` is `showPalette`, `openSettings` is
  `showSettings`, `runEntry` is `launch`. Keys are real `NSEvent`s posted into the app's own queue, so
  they take the full path — local monitors, `performKeyEquivalent`, `PalettePanel.sendEvent` — with
  no global event tap, no Accessibility grant for the driver and no race with whichever app is in
  front. An agent can never reach a state a user can't.
- **The command list is closed.** `AgentCommand` is an enum; there is no eval. A new need is a new
  case, decoded and pinned in `agent-control-test`.
- **Elements come from the AX API, read off-main.** SwiftUI serves its accessibility tree only to the
  cross-process AX API — `accessibilityChildren()` called in-process returns the hosting view alone —
  so `AgentAccessibilityReader` asks the app's own pid from a detached task while the main actor is
  suspended and free to answer. That needs Onecast Dev's Accessibility grant; `ping` reports
  `accessibilityTrusted`, and without it `elements` stays near-empty.
- **Content is redacted unless asked for.** By default a text area's value is reduced to its length,
  and so is every palette label while the clipboard screen is open. `includeContent: true` lifts both.

## Quick start

```sh
./Scripts/dev-run.sh                         # build, sign-check, relaunch, wait for the channel
Scripts/agent/onecastctl show mode=launcher until.visible=true
Scripts/agent/onecastctl type text=calc
Scripts/agent/onecastctl key key=down count=2
Scripts/agent/onecastctl state               # palette, windows with element trees, focus
Scripts/agent/onecastctl key keys='["cmd+k","down","return"]'
Scripts/agent/onecastctl waitFor text=Copied window=hud timeout=3
```

Or from anything that speaks HTTP:

```sh
H=~/Library/Application\ Support/com.onecast.app.dev/agent-control.json
curl -s -H "Authorization: Bearer $(plutil -extract token raw -o - "$H")" \
  -d '{"action":"show","mode":"clipboard"}' "http://127.0.0.1:$(plutil -extract port raw -o - "$H")/"
```

Every reply is `{"ok": true, "result": …}` or `{"ok": false, "error": "…"}`. An action's result is
the palette after it, plus `waited` seconds when it carried an `until`.

## What `state` answers

- `palette` — `visible`, `mode`, `query`, `selection`, `backStack`, `aiBar`, `collapsed`,
  `editingField`, `controlListOpen`, `frame`, and, whenever elements are read:
  - `rows` — every **rendered** row, in reading order, with its text joined by ` · `, `selected`
    and `frame`. A row is anything `selectionFrame(_:)` marks, which every selectable palette list
    already uses; it makes the row an AX container with identifier `onecast.row` and the
    `isSelected` trait. A lazy list leaves off-screen rows out, and a grid (emoji) reports one row
    per line, so `index` is the rendered place, not `selection`.
  - `barControls` — the header and footer pills as labelled (`Open Application, ↵`), from
    `BarButton` and `ActionBar`'s pills, both identified `onecast.bar`. A chip shown for an inert
    key is now a JSON assertion.
- `windows` — every visible window: `id`, `title`, `className`, `level`, `isKey`, `frame`, and its
  pruned AX `elements` (anonymous groups lifted, empty leaves dropped; `pruned: false` keeps them).
- `focus` — the key window's id, its first responder's class, the frontmost app.

## Actions

| Action | Fields | Does |
| --- | --- | --- |
| `ping` | — | build, pid, `accessibilityTrusted` |
| `state` | `includeElements` (true), `includeContent` (false), `pruned` (true) | the full snapshot |
| `show` | `mode` (`launcher`), `query` | opens a palette mode; `PaletteMode` raw values |
| `hide` | — | hides the palette, restoring focus |
| `setQuery` | `text` | sets the palette's query directly |
| `type` | `text`, `window` | one key event per character into the key (or named) window |
| `key` | `key` or `keys`, `count`, `window` | chords like `down`, `return`, `cmd+k`, `⌘⇧K`, `ctrl+n` |
| `select` | `index` | sets the palette selection |
| `activate` | `index` | optional select, then Return |
| `popToRoot` / `closeScreen` | — | the palette's own back steps |
| `openSettings` | `tab` | a `SettingsTab` case (`ai`) or title (`Window Management`) |
| `openURL` | `url` | through `AppCore.handleOpenURL`, as a deep link would arrive |
| `entries` | `query`, `kind`, `limit` (50) | launcher entries: `id`, `name`, `kind` |
| `runEntry` | `id` | launches an entry by id, as Return on its row would |
| `setAppearance` | `appearance` | `system`, `light` or `dark` |
| `press` | `match`, `window` | AX-presses the first element whose identifier, label or title matches |
| `waitFor` | any condition fields, `timeout` | waits until the condition holds |

Any action also takes `until: {…condition…}` and `timeout` (seconds, default 5, at most 60).

**Conditions** — every field given must hold at once: `visible`, `mode`, `query`, `selection`,
`minimumRows`, `text` / `absentText` (case-insensitive, in `window` or any window), `window` /
`absentWindow` (a window id). A timeout fails with what was asked and what the palette shows.

**Window ids** are the `onecast.` accessibility identifier without its prefix — `palette`, `menu`,
`dock`, `hud`, `dialog`, `notes`, `settings`, `ai-chat` — with `#2`, `#3` for a second of a kind.

## Limits

- Keys posted into the app never pass the system's event taps, so the global hotkey, the Hyper key,
  `CommandEscapeTap` and snippet keyword expansion still need [UI_TESTS.md](UI_TESTS.md)'s
  `osascript` driver.
- `type` posts one key event per character with the ANSI key code when there is one; a character off
  the layout goes with key code 0, which a text field accepts and a chord handler ignores.
- The unified log is `/usr/bin/log`: zsh's `log` is a builtin that rejects `show`.

## Files

| File | Holds |
| --- | --- |
| `Model/AgentHTTPRequest.swift` | the one HTTP/1.1 request shape and the reply framing |
| `Model/AgentCommand.swift`, `AgentRequest.swift` | the closed command list, `until` and `timeout` |
| `Model/AgentKey.swift` | chord names to key codes, characters and modifiers |
| `Model/AgentCondition.swift` | what `waitFor` checks, evaluated over a snapshot |
| `Model/AgentSnapshot.swift`, `AgentElement.swift` | the snapshot and tree pruning |
| `Model/AgentReply.swift` | the reply envelope |
| `Service/AgentControlServer.swift` | listener, handshake, token check |
| `Service/AgentKeyboard.swift` | posting key events and waiting for them to drain |
| `Service/AgentAccessibilityReader.swift` | the off-main AX walk and AX press |
| `Service/AgentWindowInspector.swift` | window ids, frames, and joining each to its AX tree |
| `UI/AgentControlCoordinator.swift` | each action, through the app's coordinators |
| `Scripts/dev-run.sh`, `Scripts/agent/` | relaunch-until-ready, `onecastctl`, the shared client |
