#!/usr/bin/env node
// A stdio MCP server over the Debug build's agent channel, so an agent gets Onecast as tools.
// Registered in the repo's .mcp.json. Each tool is one agent-channel action; see
// custom_docs/AGENT_CONTROL.md for what they do. No dependencies: newline-delimited JSON-RPC.

import { execFile } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { call } from "./client.mjs";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PROTOCOL = "2025-06-18";

const until = {
  type: "object",
  description:
    "Wait after the action until every field holds: visible, mode, query, selection, minimumRows, " +
    "text, absentText, window, absentWindow.",
};
const timeout = { type: "number", description: "Seconds to wait for `until` (default 5, max 60)." };
const window = { type: "string", description: "Window id from state, e.g. palette, settings, hud." };

/** name → [action, description, properties, required] */
const TOOLS = {
  state: ["state", "The app as data: palette mode/query/selection/rows/bar pills, every window with its accessibility tree, focus.", {
    includeElements: { type: "boolean", description: "Read AX trees (default true)." },
    includeContent: { type: "boolean", description: "Unredact clipboard and text areas (default false)." },
    pruned: { type: "boolean", description: "Lift anonymous groups (default true)." },
  }],
  show: ["show", "Open a palette mode (launcher, clipboard, ai, emoji, fileSearch, menuSearch, switchWindows, snippets, quicklinks, …).", {
    mode: { type: "string" }, query: { type: "string" }, until, timeout,
  }],
  hide: ["hide", "Hide the palette.", {}],
  set_query: ["setQuery", "Set the palette's query directly.", { text: { type: "string" }, until, timeout }, ["text"]],
  type: ["type", "Type text into the key window (or `window`) as real key events.", {
    text: { type: "string" }, window, until, timeout,
  }, ["text"]],
  key: ["key", "Press chords in order, `count` times: down, up, return, escape, tab, delete, cmd+k, ⌘⇧K, ctrl+n.", {
    keys: { type: "array", items: { type: "string" } }, count: { type: "integer" }, window, until, timeout,
  }, ["keys"]],
  select: ["select", "Set the palette selection index.", { index: { type: "integer" }, until, timeout }, ["index"]],
  activate: ["activate", "Optionally select a row, then press Return.", { index: { type: "integer" }, until, timeout }],
  pop_to_root: ["popToRoot", "Reset the palette to its root search.", {}],
  close_screen: ["closeScreen", "Leave the current palette screen.", {}],
  open_settings: ["openSettings", "Open Settings, optionally on a tab (ai, general, extensions, …).", { tab: { type: "string" }, until, timeout }],
  open_url: ["openURL", "Deliver a URL as a deep link would arrive (onecast://, raycast://).", { url: { type: "string" } }, ["url"]],
  entries: ["entries", "Search launcher entries for their ids.", {
    query: { type: "string" }, kind: { type: "string" }, limit: { type: "integer" },
  }],
  run_entry: ["runEntry", "Launch an entry by id, as Return on its row would.", { id: { type: "string" }, until, timeout }, ["id"]],
  set_appearance: ["setAppearance", "system, light or dark.", { appearance: { type: "string" } }, ["appearance"]],
  press: ["press", "AX-press the first element whose identifier, label or title matches.", {
    match: { type: "string" }, window, until, timeout,
  }, ["match"]],
  wait_for: ["waitFor", "Wait until a condition holds (same fields as `until`).", {
    visible: { type: "boolean" }, mode: { type: "string" }, query: { type: "string" },
    selection: { type: "integer" }, minimumRows: { type: "integer" }, text: { type: "string" },
    absentText: { type: "string" }, window: { type: "string" }, absentWindow: { type: "string" }, timeout,
  }],
  capture: ["capture", "Screenshot exactly one window; returns the image.", { window, path: { type: "string" } }],
  logs: ["logs", "The app's own unified log, oldest first.", {
    since: { type: "number" }, level: { type: "string" }, category: { type: "string" },
    contains: { type: "string" }, allSubsystems: { type: "boolean" }, limit: { type: "integer" },
  }],
  extension: ["extension", "The running Raycast extension command: state, failure, render tree.", {}],
  plugins: ["plugins", "Installed plugins, the running one, and whether its build matches its sources.", {}],
};

function toolList() {
  const tools = Object.entries(TOOLS).map(([name, [, description, properties, required]]) => ({
    name, description, inputSchema: { type: "object", properties, ...(required ? { required } : {}) },
  }));
  tools.push({
    name: "relaunch",
    description: "Run ./Scripts/dev-run.sh: build Debug, check signing, relaunch, wait until ready.",
    inputSchema: { type: "object", properties: { build: { type: "boolean", description: "Default true." } } },
  });
  return tools;
}

function relaunch(build) {
  return new Promise((resolve) => {
    execFile("./Scripts/dev-run.sh", build === false ? ["--no-build"] : [],
      { cwd: REPO, timeout: 20 * 60_000, maxBuffer: 8 << 20 },
      (error, stdout, stderr) => resolve({ ok: !error, text: `${stdout}${stderr}`.trim() }));
  });
}

async function runTool(name, args = {}) {
  if (name === "relaunch") {
    const { ok, text } = await relaunch(args.build);
    return { content: [{ type: "text", text }], isError: !ok };
  }
  const tool = TOOLS[name];
  if (!tool) return { content: [{ type: "text", text: `Unknown tool ${name}.` }], isError: true };
  const reply = await call({ ...args, action: tool[0] });
  const content = [{ type: "text", text: JSON.stringify(reply.ok ? reply.result : reply, null, 1) }];
  if (reply.ok && name === "capture") {
    content.push({ type: "image", mimeType: "image/png", data: readFileSync(reply.result.path).toString("base64") });
  }
  return { content, isError: !reply.ok };
}

async function answer(message) {
  switch (message.method) {
    case "initialize":
      return {
        protocolVersion: message.params?.protocolVersion ?? PROTOCOL,
        capabilities: { tools: {} },
        serverInfo: { name: "onecast", version: "1.0.0" },
        instructions:
          "Drives the running Onecast Dev build. Call relaunch after changing Swift code, then " +
          "state/show/type/key with `until` instead of sleeping. Read custom_docs/AGENT_CONTROL.md.",
      };
    case "ping":
      return {};
    case "tools/list":
      return { tools: toolList() };
    case "tools/call":
      try {
        return await runTool(message.params.name, message.params.arguments);
      } catch (error) {
        return { content: [{ type: "text", text: error.message }], isError: true };
      }
    default:
      throw Object.assign(new Error(`Method not found: ${message.method}`), { code: -32601 });
  }
}

const send = (object) => process.stdout.write(`${JSON.stringify(object)}\n`);

// One request at a time, in arrival order: a capture must see what the show before it opened.
let queue = Promise.resolve();

createInterface({ input: process.stdin }).on("line", (line) => {
  // Caught, or one rejection would leave the chain rejected and skip every later request.
  queue = queue.then(() => handle(line)).catch((error) => {
    process.stderr.write(`onecast mcp: ${error.stack ?? error}\n`);
  });
});

async function handle(line) {
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
  }
  if (message === null || typeof message !== "object" || Array.isArray(message)) {
    return send({ jsonrpc: "2.0", id: null, error: { code: -32600, message: "Invalid Request" } });
  }
  if (message.id === undefined) return; // a notification, e.g. notifications/initialized
  try {
    send({ jsonrpc: "2.0", id: message.id, result: await answer(message) });
  } catch (error) {
    send({ jsonrpc: "2.0", id: message.id, error: { code: error.code ?? -32603, message: error.message } });
  }
}
