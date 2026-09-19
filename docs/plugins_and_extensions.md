# Plugins & extensions

Onecast has two ways to add commands without touching the app: **native Swift plugins** and
**JavaScript extensions**. This is the develop → build → install reference and the map of the host
code behind each. The authoring guides — how to *write* one — live in the add-ons repo
([`plugins/SWIFT_PLUGINS.md`](https://github.com/jhasubhash/onecast_addons), `extensions/GOTCHAS.md`).

|  | Native plugin | JS extension |
|---|---|---|
| Language | Swift + SwiftUI | JavaScript/TypeScript (`@raycast/api`) |
| Runs as | in-process dylib, full app privileges | JavaScriptCore, host-mediated |
| You ship | `manifest.json` + `.swift` sources | `package.json` + built `<command>.js` + `assets/` |
| Build | **the app compiles it from source** | `esbuild`, by you, before install |
| Installs to | `~/Library/Application Support/<bundle id>/plugins/<name>/` | `…/<bundle id>/extensions/<name>/` |
| Trust | unsandboxed native code — enable only what you trust | sandboxed-ish; still runs your JS |

`<bundle id>` is the channel: `com.onecast.app` for a release build, `com.onecast.app.dev` for the
Debug `Onecast Dev.app`.

---

## Native plugins

### The workflow

A plugin is a folder with a `manifest.json` and one or more `.swift` files. **There is no build
step you run** — drop the folder into the plugins directory and Onecast compiles it:

```
~/Library/Application Support/com.onecast.app.dev/plugins/hello-plugin/
  manifest.json
  HelloPlugin.swift            # any .swift under the folder; a Sources/ tree also works
```

```json
{ "name": "Hello", "identifier": "com.example.hello", "subtitle": "…", "icon": "hand.wave" }
```

- `name`, `identifier` are required; `subtitle`, `icon` (SF Symbol) and `module` are optional.
- `module` is the Swift `-module-name`; when omitted it is derived from `name`
  (`Stock Quotes` → `StockQuotes`). The `@_cdecl("onecastPluginCreate")` entry point is
  module-independent, so this only matters if two plugins would otherwise collide.

Then **Settings → Plugins → Enable plugins** (a one-time consent, because a plugin is native code
running with the app's full privileges), and search the plugin by name in the launcher.

### What the app does

1. **Scan** — `PluginCatalog.scan` finds each folder with a readable `manifest.json` and at least one
   `.swift` (recursively; a `build`/`.build` subfolder is skipped), and fingerprints the sources by
   path/size/mtime.
2. **Build** — `PluginBuilder.build` runs one `swiftc` (through `xcrun`, so it inherits the SDK) that
   emits a dylib linking the app's own embedded `OnecastPluginKit`, then ad-hoc signs it. Output and
   the fingerprint are cached under `~/Library/Caches/<bundle id>/PluginBuilds/<identifier>/`, so an
   unchanged plugin never recompiles. A missing toolchain or a compile error surfaces in the palette
   where the plugin would run, carrying the diagnostic. Each installed plugin is pre-warmed off-main
   on scan, so launching one is instant.
3. **Load** — `PluginLoader.load` `dlopen`s a **content-addressed copy** of the built dylib and calls
   `onecastPluginCreate`. Because the copy is keyed by content hash, a rebuild maps the fresh bytes on
   the next open with no app relaunch.

**Editing is live.** The plugins folder is watched: dropping a plugin in, or editing a source, is
picked up within a moment and rebuilt in the background. Reopening the plugin maps the new build; the
currently-running session keeps its image until you leave it.

### Requirements

A Swift toolchain — full **Xcode** or the **Command Line Tools** (`xcode-select --install`). Nothing
else; the app carries the framework and does the rest.

### How the app can compile against itself

Plugins compile against `OnecastPluginKit`, built with `BUILD_LIBRARY_FOR_DISTRIBUTION` so it emits a
stable textual `.swiftinterface`. Xcode strips a framework's Swift module when it embeds it, so the
`project.yml` post-build step **Restore OnecastPluginKit interface** copies the `.swiftinterface`
(only the interface — the binary swiftmodule is compiler-version-specific) back into the embedded
framework, wires its top-level `Modules` symlink, and re-signs it. That is the one packaging move that
lets the shipped app build a plugin against its own framework. The
`com.apple.security.cs.disable-library-validation` entitlement lets the app `dlopen` the ad-hoc-signed
result.

### Host code

| File | Owns |
|---|---|
| `Features/Plugins/Service/PluginCatalog.swift` | manifest + install model, `scan`, source fingerprint |
| `Features/Plugins/Service/PluginBuilder.swift` | the `swiftc`/`codesign` compile, cache, toolchain check |
| `Features/Plugins/Service/PluginLoader.swift` | content-addressed `dlopen`, entry-point handshake |
| `Features/Plugins/Service/PluginManager.swift` | installed set, watcher, prewarm, one running session |
| `Features/Plugins/UI/PluginCoordinator.swift` | enable/consent, launching, deep-link routing |
| `Features/Plugins/UI/PluginScreen.swift` | the palette body for a running plugin |
| `Features/Plugins/UI/PluginWindowController.swift` | pop-out plugin windows |
| `OnecastPluginKit/` | the public contract a plugin links (`project.yml` target) |

The plugin API surface a plugin author uses is documented in the add-ons repo's `SWIFT_PLUGINS.md`.

---

## JavaScript extensions

### The workflow

Extensions are **Raycast-compatible**: the same `package.json` manifest and `@raycast/api` surface,
run natively in JavaScriptCore. You build them yourself, then point Onecast at the folder.

```sh
cd extensions/<name>
npm ci
npm run build          # esbuild writes one <command>.js beside package.json, per declared command
```

Install from **Settings → Extensions → Add**, picking the built folder. Onecast copies exactly what an
install needs — `package.json`, each declared command's `<command>.js`, and `assets/` — into
`~/Library/Application Support/<bundle id>/extensions/<name>/`. After re-installing, Settings →
Extensions rescans (or use the **Reload Extensions** command).

Launch a command directly with a deep link:
`onecast://extensions/<author>/<extension-name>/<command-name>` (the `raycast://` scheme also works).

### Requirements

Node, for the build only. The app ships its own committed runtime
(`Resources/RaycastRuntime.generated.js`), so running an extension needs no Node. Hardened-runtime JIT
is allowed (`com.apple.security.cs.allow-jit`) for JavaScriptCore.

### Host code

| File | Owns |
|---|---|
| `Features/Extensions/Service/ExtensionCatalog.swift` | install model, `scan`/`install`, per-command bundle lookup |
| `Features/Extensions/Service/ExtensionRuntime.swift` | the `@raycast/api` runtime over JavaScriptCore |
| `Features/Extensions/Service/ExtensionFetcher.swift` | fetching an extension from a store/URL |
| `Features/Extensions/Model/ExtensionManifest.swift` | the `package.json` shape and its commands |
| `Features/Extensions/UI/ExtensionScreen.swift` | rendering a command's `<List>`/`<Grid>`/detail |

Where Onecast's runtime differs from real Raycast — the shared palette search across a push stack,
selection-by-index on push, the subset of List props read, `fs.cpSync` — is catalogued in the add-ons
repo's `extensions/GOTCHAS.md`. Read it before writing a multi-screen extension.
