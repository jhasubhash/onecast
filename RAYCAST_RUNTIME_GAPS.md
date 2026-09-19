# Raycast runtime gaps

Onecast runs Raycast extensions in **JavaScriptCore**, not Node. Real Raycast runs on **Node.js**, so
"a gap" is anything Node (or a browser API an extension bundle assumes) exposes that our JSC runtime
does not — or exposes with different semantics. This file is the running backlog of those gaps.

- **Runtime source:** `Scripts/raycast-runtime/src/` (bundled to `Onecast/Resources/RaycastRuntime.generated.js` by `node Scripts/raycast-runtime/build.mjs`; the bundle is committed).
- **Tests:** `Scripts/raycast-runtime/fixtures.mjs` (run `node fixtures.mjs` after `npm install`).
- **Guiding rule:** prefer **Node parity**. Add what Node exposes; do *not* add browser-only globals
  Node lacks (e.g. `localStorage`, `window`, `document`) — an isomorphic library feature-detects those
  to pick a browser path Onecast can't satisfy, so adding them makes things *worse*, not better.

## How to re-check (capability probe)

Drop a throwaway no-view extension whose command `console.log`s `typeof` of each global, run it against
a **Debug** build launched from a terminal (so `[extension log]` prints flush), and read the JSON. The
last run's results seed the tables below.

## Fixed (this pass)

| Gap | Symptom | Fix |
| --- | --- | --- |
| `Readable.push` emitted a `data` event for a **zero-length** chunk | sips Flip/Scale/Resize/etc. threw "Finder Selection Error" on empty stderr | `src/streams.js` — ignore empty chunks in byte mode, matching Node |
| `Symbol.dispose` / `Symbol.asyncDispose` missing | sips Remove Background threw `TypeError: Object not disposable` (its `await using` temp file) | `src/polyfills.js` — define as `Symbol.for("Symbol.dispose")` (the value the bundler helper falls back to) |
| `navigator`, `reportError` missing | isomorphic libraries reading them throw `ReferenceError` | `src/polyfills.js` — minimal Node-parity `navigator`; `reportError` → uncaught sink |

## Missing globals (backlog, priority order)

| Global | Present? | Impact | Notes / approach |
| --- | --- | --- | --- |
| **`crypto.subtle`** (WebCrypto) | ✗ (`crypto.randomUUID`/`getRandomValues` ✓) | **High** — hashing, HMAC signing, PKCE. Node has full WebCrypto. | Bridge to the existing `crypto` host calls (`createHash`/`createHmac` already work). **Implement fully** (`digest`, `importKey`, `sign`/`verify`, `encrypt`/`decrypt`, `deriveBits`) — a *partial* subtle is worse than none, because libraries that fall back when `subtle` is absent would instead take the WebCrypto path and fail deeper. |
| **`WebSocket`** | ✗ | **High** — any realtime extension. | Needs a native socket bridge in Swift (`net`/`tls` are refuse-on-use). Largest item. |
| **`EventSource`** (SSE) | ✗ | Medium — streaming APIs. | Could layer over `fetch` streaming, but the fetch bridge is currently buffered (one reply); needs incremental body delivery first. |
| **`TextEncoderStream` / `TextDecoderStream`** | ✗ | Medium — `fetch().body` piped through a decoder. | Implementable as `Transform`s on the existing streams infra. |
| **`CompressionStream` / `DecompressionStream`** | ✗ | Low–Medium — web gzip. | `zlib` host calls exist; wrap as `Transform`s. |
| **`BroadcastChannel`** | ✗ | Low — single JS context, so same-context delivery is a valid impl. | Cheap if needed. |
| **`MessageChannel` / `MessagePort`** | ✗ | Low — some browser scheduler shims post to a port for macrotasks. | Cheap; Onecast already owns its scheduler. |
| **`URLPattern`** | ✗ | Low — routing libs. | Rare in extensions. |
| **`Symbol.metadata`** | ✗ | Low — decorator metadata. | Rare. |
| Global **`AsyncIterator`** | ✗ | Low — iterator-helpers proposal. `Symbol.asyncIterator` itself works. | Rare. |

Present and confirmed working: `structuredClone`, `queueMicrotask`, `Promise.withResolvers`/`any`/
`allSettled`, `Array.fromAsync`, `Object.groupBy`/`Map.groupBy`, `Object.hasOwn`, `Array.at`/`findLast`,
`String.replaceAll`/`at`, `Symbol.dispose`/`asyncDispose`, `Iterator`, `crypto.randomUUID`/
`getRandomValues`, `fetch`/`Request`/`Response`/`Headers`, `AbortSignal.timeout`/`any`, `Blob.stream`/
`arrayBuffer`, `ReadableStream.getReader`.

## Intentionally omitted (do not add)

Node lacks these too, so adding them breaks isomorphic browser-detection:

- `localStorage`, `window`, `document`, `sessionStorage`.

## Refuse-on-use Node modules (deliberate capability gaps)

These resolve but throw when used (`src/node-shims.js`), so a bundle that merely references them still
loads. An extension that actually needs one won't run — by design:

- `net`, `tls`, `dns` — raw sockets.
- `http` / `https` server bits (client `request`/`get` work, routed over the fetch bridge).
- `worker_threads`, `vm`, `cluster` (single-threaded, no eval sandbox).
- `child_process.fork`, `fs.watch`, `zlib` brotli, Windows file paths.

## Semantic edge-cases (the hard class)

Both bugs fixed this pass were **not** missing APIs — they were behavioral mismatches inside shims
(an empty stream still emitting `data`; a computed dispose key degrading). These can't be enumerated by
a probe; they surface only when an extension exercises a shim's edge. When one appears: reproduce
against a terminal-launched Debug build, read the `[extension error]` stack, and fix the shim in
`src/` to match Node's observable behavior, with a `fixtures.mjs` regression.
