// The agent channel's client: reads the handshake a running Debug build writes, POSTs a command.
// Shared by onecastctl and the MCP server. See custom_docs/AGENT_CONTROL.md.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const BUNDLE_ID = process.env.ONECAST_BUNDLE_ID ?? "com.onecast.app.dev";
export const HANDSHAKE = join(
  homedir(), "Library", "Application Support", BUNDLE_ID, "agent-control.json");

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function handshake() {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(HANDSHAKE, "utf8"));
  } catch {
    throw new Error(`No agent channel: ${HANDSHAKE} is missing. Run ./Scripts/dev-run.sh first.`);
  }
  // A crashed build leaves its handshake behind; its port may already belong to someone else.
  if (!alive(parsed.pid)) {
    throw new Error(`The Onecast Dev that wrote ${HANDSHAKE} (pid ${parsed.pid}) is not running.`);
  }
  return parsed;
}

export async function call(command, { timeoutMs = 70_000 } = {}) {
  const { port, token } = handshake();
  const response = await fetch(`http://127.0.0.1:${port}/`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(command),
    signal: AbortSignal.timeout(timeoutMs),
  });
  return response.json();
}

/// Polls `ping` until a build answers, for scripts that just launched one.
export async function waitReady(seconds = 20) {
  const deadline = Date.now() + seconds * 1000;
  let last;
  while (Date.now() < deadline) {
    try {
      const reply = await call({ action: "ping" }, { timeoutMs: 2000 });
      if (reply.ok) return reply.result;
    } catch (error) {
      last = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`Onecast Dev did not answer within ${seconds}s: ${last?.message ?? "no reply"}`);
}
