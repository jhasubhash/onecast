---
name: onecast-drive
description: Build, relaunch and drive the Onecast Dev app to verify a change or debug a UI issue — open palette screens, type, press keys, wait on conditions, read state/rows/AX trees, capture a window, read logs, inspect a running Raycast extension or native plugin. Use when asked to run, test, screenshot or debug Onecast in the real app, or before claiming any UI change is done.
---

# Drive Onecast Dev

The Debug build opens an agent channel (custom_docs/AGENT_CONTROL.md). Use it instead of
`osascript` keystrokes, `sleep` and full-screen screenshots.

## Loop

1. **Rebuild and relaunch** after any Swift change: the `relaunch` MCP tool, or
   `./Scripts/dev-run.sh` (`--no-build` to only restart). It checks signing, quits the old
   instance and returns once the channel answers. Never verify against a stale build.
2. **Act** with the `onecast` MCP tools (or `Scripts/agent/onecastctl <action> field=value`):
   `show`, `type`, `key`, `select`, `activate`, `run_entry`, `open_settings`, `press`.
3. **Wait on facts, never on time**: give the action an `until`
   (`{"mode":"clipboard"}`, `{"minimumRows":1}`, `{"text":"Copied","window":"hud"}`) or call
   `wait_for`. A timeout tells you what the palette actually shows.
4. **Read the result as data**: `state` → `palette.mode/query/selection/rows/barControls` and each
   window's `elements`. Check the selected row in `rows`, not by eye.
5. **Look** only for visual questions: `capture` (one window). Judge the image yourself.
6. **Explain failures**: `logs` (`category=…`, `level=error`, `allSubsystems=true` for SwiftUI
   faults), `extension` for a Raycast command's render tree and failure, `plugins` for whether a
   plugin's mapped build matches its sources.

## Rules

- Debug channel only (`Onecast Dev`, `com.onecast.app.dev`); the channel does not exist in Release.
- If `ping`/`state` reports `accessibilityTrusted: false`, element trees and rows are empty: ask
  the user to grant Onecast Dev Accessibility. Captures without Screen Recording use
  `cacheDisplay` (no glass) — say so if it matters.
- Clipboard text and text areas are redacted by default. Pass `includeContent: true` only when the
  task needs the text, and never echo personal content back.
- `run_entry` on a menu-bar extension command enables it persistently; avoid unless asked.
- The global hotkey, Hyper key and snippet expansion bypass the channel: verify those with the
  `osascript` driver in custom_docs/UI_TESTS.md.
- A UI change is done per custom_docs/UI_TESTS.md §8; new failure modes go in its §7 register.
