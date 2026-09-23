# OneCast

**A native macOS launcher with an AI cockpit built in.** One keystroke starts apps, pastes from a
rich clipboard, runs your Raycast extensions natively, and holds a real conversation with your own AI
models — SwiftUI and AppKit, no Electron, no telemetry, comfortably under 100 MB of RAM.

> OneCast is a personal, opinionated fork of [tinycast](https://github.com/jhasubhash/tinycast). It
> started from that repo and has since **deviated substantially** — a whole AI, plugin and automation
> layer upstream doesn't carry — and is developed independently. The original fork stays up for
> lineage.

<p align="center">
  <a href="https://github.com/jhasubhash/onecast/releases/latest">
    <img alt="Latest release"
         src="https://img.shields.io/github/v/release/jhasubhash/onecast?sort=semver&style=flat&label=release&color=1F6FEB"></a>
  <img alt="Swift 6.0"
       src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white">
  <img alt="macOS 26 or later"
       src="https://img.shields.io/badge/macOS-26%2B-000000?style=flat&logo=apple&logoColor=white">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
  <a href="https://www.buymeacoffee.com/subhashjha">
    <img alt="Buy Me a Coffee"
         src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Tip%20the%20dev-FFDD00?style=flat&logo=buymeacoffee&logoColor=black"></a>
</p>

<p align="center">
  <img src="docs/screenshot.png" alt="OneCast command palette" width="720">
</p>

OneCast keeps everything that makes the base app small and fast — zero third-party dependencies, a
single hotkey, native SwiftUI — and adds the pieces I reach for every day: assistants I can summon by
name, a scheduler that speaks plain English, and a Swift plugin runtime for surfaces the JavaScript
extension API can't reach.

## Highlights — what OneCast adds

### AI, front and center

- **Floating AI Chat bar** — a dedicated hotkey drops a compact *"Ask anything…"* composer anywhere on
  screen, sharing the palette's chat and history, with its own per-display placement and an optional
  *stay-open-on-blur* mode.
- **Configured Assistants** — save named assistants, each with its own hotkey, tint, model and skills,
  and summon any of them straight to a chat bar.
- **Bring your own CLI** — route an installed **Claude**, **Codex**, **GitHub Copilot** or **OpenCode**
  CLI as a first-class provider. Per assistant you can opt into **MCP tool calling**, **shell tools**
  (so a script-based skill like a Jira query actually runs), and **environment variables** stored one
  Keychain item at a time.
- **Streamed reasoning** — a model's thinking streams live into the transcript (togglable), with a
  reasoning-effort picker across Claude and Copilot models.
- **On-device tool calling** — Apple Intelligence (FoundationModels) runs host tools, including the
  scheduler, entirely in-process.

### Native Swift plugins

- **Compiled SwiftUI plugins** load into the palette through `OnecastPluginKit` and render real
  SwiftUI — the BetterTouchTool-style escape hatch for anything the JavaScript extension API can't
  express, alongside the existing Raycast extension runtime.
- **Pin & deep-link** a plugin's inner view onto the launcher (it's stored as an ordinary Quicklink,
  so it inherits aliases, shortcuts and backup), or **pop it out** into its own borderless, resizable
  window.

### Automation

- **Task scheduler** — run a script or fire a notification on a rule, created and edited right from the
  launcher, with a natural-language *"remind me…"* fallback and an on-device parser for phrases like
  *"in 20 minutes"*.

### Faster editing

- **Inline ⌘K editing** — change an app's alias or global shortcut in a box on the row itself
  (Raycast-parity; the menu stays open, a taken chord is flagged inline), and edit or rename a
  Quicklink the same way. Extension commands are bindable to hotkeys too.
- **Smarter Translate** — an optional AI engine handles transliterated text Apple's translator
  misreads (romanized Hindi and the like), plus an auto-direction language pair so one shortcut flips
  English ↔ Hindi with no dialog.

## Features

Everything the base app does is still here:

- **App launcher** — fuzzy search, pin favorites, see and quit what's running.
- **Global & per-app hotkeys** — bind a chord to anything, including a double-tapped modifier or a
  Hyper key.
- **Clipboard history** — text and images, searchable from the palette.
- **Inline calculator** — math plus unit and currency conversions as you type.
- **Floating note** — one always-available Markdown scratchpad.
- **Snippets** — keyword-triggered text expansion, off until you turn it on.
- **Quicklinks** — parameterised URLs and deep links, aliasable and bindable.
- **Window management** — move, resize and tile with keyboard commands.
- **Emoji picker** — a searchable grid, one keystroke away.
- **Quick Actions** — fix grammar, rewrite, translate or summarize the selection in any app.
- **Raycast extensions** — run the ones you already have, rendered natively as SwiftUI.
- **Backup & import** — export your setup to a file, or import from Raycast.

## Extensions & plugins

My own OneCast extensions and native Swift plugins live in a separate repo —
**[onecast_addons](https://github.com/jhasubhash/onecast_addons)** — so they cost zero rebase
surface and survive every release untouched. Build them there, then add them from
**Settings → Extensions**.

## Install

Add the tap:

```sh
brew trust --tap jhasubhash/onecast   # required for third-party taps
brew tap jhasubhash/onecast
```

Then run the line that matches your Mac:

| Your Mac                                           | Install                                  |
| -------------------------------------------------- | ---------------------------------------- |
| Apple silicon, macOS 26 or newer                   | `brew install --cask onecast`            |
| Intel, macOS 26                                    | `brew install --cask onecast-universal`  |
| macOS 15 Sequoia <sub>(unmaintained)</sub>         | `brew install --cask onecast-sequoia`    |

Not sure which you have? **Apple menu → About This Mac** — Homebrew checks too and refuses the wrong
build. Want early builds? `brew install --cask onecast@beta` installs `OneCast Beta.app` beside the
stable app with its own settings and permissions.

Homebrew clears the macOS quarantine flag on install and update, so there's nothing else to run.
Grabbing a DMG from [Releases](https://github.com/jhasubhash/onecast/releases) instead? OneCast is
self-signed, so clear the flag once:
`xattr -dr com.apple.quarantine "/Applications/OneCast.app"`.

## Permissions

**Accessibility** is the one that matters: it's needed to paste or expand text into another app and to
listen for snippet keywords. You're prompted the first time a feature needs it — grant it in **System
Settings → Privacy & Security → Accessibility**. Snippets ship disabled, and keystrokes are matched
locally, never stored and never sent anywhere.

Everything else asks for its own access on first use, never up front — **Notifications** for the
scheduler, **Calendar** to join meetings, and **Camera** / **Bluetooth** for their respective actions.

## Quick start

1. Open **Settings → General** and record a global shortcut to summon OneCast.
2. Press it anywhere — the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑ / ↓** move, **Esc** dismisses.
4. **Settings → AI** — add a model or an installed CLI, then bind the **Floating AI Chat bar** (or a
   named Assistant) to its own hotkey.
5. **Settings → Shortcuts / Snippets / Scheduler** — bind commands, add expansions, or schedule a
   reminder in plain English.

## Building from source

Fork-specific build and signing notes live in **[CUSTOM.md](custom_docs/CUSTOM.md)**; the base
toolchain, packaging and release workflow are in **[docs/development.md](docs/development.md)**, and
**[docs/](docs/README.md)** indexes the architecture, engineering standards, design system and one
document per feature.

## Contributing

OneCast is a personal fork shaped around how I work, so its feature set follows my own needs rather
than an open roadmap. Issues and pull requests are welcome, but it is not a drop-in replacement for
upstream — see **[CUSTOM.md](custom_docs/CUSTOM.md)** for how this fork tracks and deliberately
diverges from [tinycast](https://github.com/jhasubhash/tinycast). Security reports go through
**[SECURITY.md](SECURITY.md)**, not the issue tracker.

## Support

OneCast is free and open source. If it earns a spot in your daily flow, feel free to contribute back 
and keep it actively maintained:

## License

[AGPL-3.0](LICENSE). OneCast is a modified fork of [tinycast](https://github.com/jhasubhash/tinycast)
(Copyright © 2026 Abue Ammar) and stays under the same license. Modifications © 2026 Subhash Jha.
