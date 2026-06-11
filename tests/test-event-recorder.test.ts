/**
 * test-event-recorder.test.ts
 *
 * Records every observable event and hook invocation that OpenCode emits
 * during a scripted session.  Designed as a living specification: run it
 * against a new opencode version to see exactly what changed.
 *
 * ## Hook channels
 *
 * OpenCode delivers events through two distinct channels:
 *
 *   event hook   — receives the typed Event union (session.*, message.*, todo.updated,
 *                  file.*, tui.*, etc.)  All docs-listed events go here.
 *   named hooks  — separate call sites that are NOT in the Event union and never
 *                  appear via the event hook.
 *
 * To rediscover named hooks after an opencode version bump:
 *
 *   grep -E '^\s+"[a-z]' \
 *     $(npm root)/@opencode-ai/plugin/dist/index.d.ts 2>/dev/null || \
 *   grep -E '^\s+"[a-z]' \
 *     ~/.cache/opencode/node_modules/@opencode-ai/plugin/dist/index.d.ts
 *
 * This prints every string-keyed member of the Hooks interface — the named hooks.
 * Cross-reference against the Event union in @opencode-ai/sdk dist/gen/types.gen.d.ts
 * (search for `export type Event =`) to confirm which belong to each channel.
 *
 * Current named hooks in the Hooks interface (1.14.48):
 *   chat.message            — fires once per /session/{id}/message POST (per LLM call)
 *   chat.params             — modify temperature/topP/etc before each LLM call
 *   chat.headers            — inject HTTP headers on each LLM call
 *   permission.ask          — intercept tool permission prompts
 *   command.execute.before  — fires before slash commands run
 *   tool.execute.before     — fires before each tool call
 *   tool.execute.after      — fires after each tool call
 *   shell.env               — fires for every shell invocation (tool + user terminal)
 *   experimental.chat.messages.transform
 *   experimental.chat.system.transform
 *   experimental.session.compacting
 *   experimental.text.complete
 *
 * The recorder captures the ones that fire in a normal two-turn session:
 *   chat.message, command.execute.before, tool.execute.before/after, shell.env
 *
 * Named hooks NOT recorded (require conditions this test doesn't exercise):
 *   permission.ask       — needs a tool call with permission: "ask" config
 *   chat.params          — fires on every LLM call but adds no observational value here
 *   chat.headers         — same
 *   experimental.*       — compaction and message transform hooks
 *
 * ## Snapshot comparison
 *
 * `toMatchSnapshot()` records the ordered event-type sequence and the count map.
 * After upgrading opencode, run:
 *   bun test test-event-recorder.test.ts --update-snapshots
 * to accept new behaviour deliberately.
 *
 * Usage:
 *   cd tests && HARNESS_DEBUG=1 bun test test-event-recorder.test.ts 2>&1 | less
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer } from "llm-mock-server";
import { rm, readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import {
  createFixtureRepo,
  createSession,
  findFreePort,
  sendPromptAndWait,
  startOpencode,
  verifySession,
} from "./harness";

// ---------------------------------------------------------------------------
// Recorded event shape
// ---------------------------------------------------------------------------

type RecordedEvent = {
  /** ms since plugin was first instantiated */
  t: number;
  source:
  | "hook.event"
  | "hook.chat.message"
  | "hook.command.before"
  | "hook.tool.before"
  | "hook.tool.after"
  | "hook.shell.env";
  type: string;
  properties?: unknown;
};

// ---------------------------------------------------------------------------
// Recorder plugin source
//
// Written to fakeHome/.config/opencode/plugins/recorder.ts so it is the
// only plugin that loads (no temper, no skills).
//
// Named hooks are listed explicitly because they are on SEPARATE delivery
// channels from the event hook — they never appear via event.type in the
// event stream.  Evidence: the full event recording with temper showed
// chat.message/tool.*/shell.env only via their own hooks, never via hook.event.
// ---------------------------------------------------------------------------

const recorderPluginSrc = (logPath: string) => String.raw`
import { appendFile } from "node:fs/promises";

const logPath = "${logPath}";
const startTs = Date.now();

async function record(entry) {
  if (!logPath) return;
  await appendFile(logPath, JSON.stringify(entry) + "\n").catch(() => {});
}

export const RecorderPlugin = async () => ({
  "shell.env": async (input) => {
    await record({ t: Date.now() - startTs, source: "hook.shell.env", type: "shell.env",
      properties: { cwd: input.cwd, sessionID: input.sessionID } });
  },
  "chat.message": async (input) => {
    await record({ t: Date.now() - startTs, source: "hook.chat.message", type: "chat.message",
      properties: { sessionID: input.sessionID, agent: input.agent } });
  },
  "command.execute.before": async (input) => {
    await record({ t: Date.now() - startTs, source: "hook.command.before", type: "command.execute.before",
      properties: { command: input.command, sessionID: input.sessionID } });
  },
  "tool.execute.before": async (input) => {
    await record({ t: Date.now() - startTs, source: "hook.tool.before", type: "tool.execute.before",
      properties: { tool: input.tool, sessionID: input.sessionID } });
  },
  "tool.execute.after": async (input) => {
    await record({ t: Date.now() - startTs, source: "hook.tool.after", type: "tool.execute.after",
      properties: { tool: input.tool, sessionID: input.sessionID } });
  },
  event: async ({ event }) => {
    await record({ t: Date.now() - startTs, source: "hook.event", type: event.type,
      properties: event.properties });
  },
});
`;

// ---------------------------------------------------------------------------
// Test state
// ---------------------------------------------------------------------------

let mock: MockServer;
let newSessionEvents: RecordedEvent[] = [];
let restoredSessionEvents: RecordedEvent[] = [];
let ocVersion: string = "unknown";

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  mock = await createMock({ port: mockPort, logLevel: "none" });
  mock.when((req) => req.toolNames.length === 0).reply("Test session title");
  // Two-turn: bash tool call → plain text reply.  Exercises tool hooks + session.idle.
  mock.when((req) => req.toolNames.length > 0).replySequence([
    { reply: { tools: [{ name: "bash", args: { command: "echo hello", description: "echo" } }] } },
    { reply: { text: "Done." } },
    { reply: { text: "All done." } }, // fallback
    { reply: { text: "Restore done." } }, // restore prompt fallback
  ]);

  const dir = await createFixtureRepo();
  const hookLogPath = join(dir, ".opencode", "hook-events.ndjson");

  // Project config: mock provider, no plugins (plugin dir isolation handled via HOME)
  await writeFile(join(dir, "opencode.json"), JSON.stringify({
    $schema: "https://opencode.ai/config.json",
    share: "disabled",
    permission: "allow",
    plugin: [],
    provider: {
      "llm-mock": {
        npm: "@ai-sdk/openai-compatible",
        name: "LLM Mock",
        options: { baseURL: `${mock.url}/v1`, apiKey: "test" },
        models: {
          "mock-model": {
            name: "Mock Model",
            tool_call: true,
            limit: { context: 200_000, output: 4096 },
            cost: { input: 0, output: 0 },
          },
        },
      },
    },
    model: "llm-mock/mock-model",
  }, null, 2));

  const fakePluginsDir = join(dir, ".opencode", "plugins");
  await mkdir(fakePluginsDir, { recursive: true });
  await writeFile(join(fakePluginsDir, "recorder.ts"), recorderPluginSrc(hookLogPath));

  const { stop, restart } = await startOpencode(dir, ocPort, true);

  const sessionID = await createSession(ocPort, dir);
  await sendPromptAndWait(ocPort, sessionID, "Run a quick echo command.", mock);
  await new Promise((r) => setTimeout(r, 2_000)); // trailing events

  // Read Phase 1 (new session) events, then clear the log before restart
  try {
    const raw = await readFile(hookLogPath, "utf8");
    newSessionEvents = raw.split("\n").filter(Boolean).map((l) => JSON.parse(l) as RecordedEvent);
  } catch {
    newSessionEvents = [];
  }
  await writeFile(hookLogPath, "");

  // Phase 2: restart against the same dir and session
  await restart();
  await verifySession(ocPort, sessionID);
  await new Promise((r) => setTimeout(r, 5_000)); // silent window — capture spontaneous restore events
  await sendPromptAndWait(ocPort, sessionID, "Run a quick echo command.", mock);
  await new Promise((r) => setTimeout(r, 2_000)); // trailing events

  stop();

  try {
    const raw = await readFile(hookLogPath, "utf8");
    restoredSessionEvents = raw.split("\n").filter(Boolean).map((l) => JSON.parse(l) as RecordedEvent);
  } catch {
    restoredSessionEvents = [];
  }

  ocVersion = (newSessionEvents.find((e) => e.type === "session.updated")?.properties as any)?.info?.version ?? "unknown";

  for (const [label, evs] of [["NEW SESSION", newSessionEvents], ["RESTORED SESSION", restoredSessionEvents]] as [string, RecordedEvent[]][]) {
    process.stderr.write(`\n=== OPENCODE EVENT RECORDING — ${label} (${ocVersion}) ===\n`);
    for (const e of evs) {
      const props = e.properties ? JSON.stringify(e.properties).slice(0, 280) : "";
      process.stderr.write(
        `  +${String(e.t).padStart(5)}ms  [${e.source.padEnd(22)}]  ${e.type.padEnd(30)}  ${props}\n`
      );
    }
    process.stderr.write(`=== END ${label} RECORDING ===\n\n`);
  }

  await rm(dir, { recursive: true, force: true }).catch(() => { });
}, 120_000);

afterAll(async () => { await mock?.stop(); });

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function eventsOfType(type: string, src: RecordedEvent[] = newSessionEvents) {
  return src.filter((e) => e.type === type);
}

// ---------------------------------------------------------------------------
// Snapshot: event-type sequence — the regression baseline for version upgrades
// ---------------------------------------------------------------------------

describe("event recorder — snapshot baseline", () => {
  it("event type sequence matches snapshot", () => {
    const sequence = newSessionEvents.map((e) => `[${e.source}] ${e.type}`);
    expect(sequence).toMatchSnapshot();
  });

  it("event type counts match snapshot (order-independent, for readable diffs)", () => {
    const typeCounts: Record<string, number> = {};
    for (const e of newSessionEvents) {
      const k = `[${e.source}] ${e.type}`;
      typeCounts[k] = (typeCounts[k] ?? 0) + 1;
    }
    expect(typeCounts).toMatchSnapshot();
  });
});

// ---------------------------------------------------------------------------
// Live assertions — concrete behaviours, fail on absence
// ---------------------------------------------------------------------------

describe("event recorder — session lifecycle", () => {
  it("session.updated: properties.sessionID is present at runtime (v1 types omit it)", () => {
    // v1 SDK type declares EventSessionUpdated.properties as { info: Session } with no sessionID.
    // v2 SDK adds sessionID.  At runtime in 1.14.48 the field IS present (server emits v2-shaped data).
    // Temper's `(event.properties as any).sessionID` cast is a type-only workaround, not a runtime fix.
    const ev = eventsOfType("session.updated");
    expect(ev.length).toBeGreaterThan(0);
    for (const e of ev) {
      const hasDirectID = typeof (e.properties as any)?.sessionID === "string";
      console.error(`+${e.t}ms session.updated: properties.sessionID=${(e.properties as any)?.sessionID ?? "(MISSING)"}`);
      expect(hasDirectID).toBe(true);
    }
  });

  it("session.created does fire on a fresh session", () => {
    // Temper synthesizes session.created dispatch via session.status → hydrateSession.
    // If this starts firing in a later version, temper could listen to it directly.
    const ev = eventsOfType("session.created");
    expect(ev.length).toBe(1);
  });

  it("session.status{idle} and session.idle fire atomically (same event batch)", () => {
    const statusIdle = eventsOfType("session.status").filter((e) => (e.properties as any)?.status?.type === "idle");
    const idle = eventsOfType("session.idle");
    expect(statusIdle.length).toBeGreaterThan(0);
    expect(idle.length).toBeGreaterThan(0);
    const gap = idle[0].t - statusIdle[0].t;
    console.error(`session.status{idle} → session.idle gap: ${gap}ms`);
    expect(gap).toBeGreaterThanOrEqual(0);
    expect(gap).toBeLessThan(50); // same internal dispatch, not a polling timeout
  });

  it("session.idle fires after tool.execute.after completes (causal, not timeout-based)", () => {
    const toolAfter = newSessionEvents.filter((e) => e.source === "hook.tool.after");
    const idle = eventsOfType("session.idle");
    expect(toolAfter.length).toBeGreaterThan(0);
    expect(idle.length).toBeGreaterThan(0);
    const lastToolT = Math.max(...toolAfter.map((e) => e.t));
    const firstIdleT = idle[0].t;
    console.error(`last tool.execute.after: +${lastToolT}ms → session.idle: +${firstIdleT}ms (gap: ${firstIdleT - lastToolT}ms)`);
    expect(firstIdleT).toBeGreaterThan(lastToolT);
  });
});

describe("event recorder — separate hook channels", () => {
  it("chat.message fires on its own hook, never via the event hook", () => {
    const viaHook = newSessionEvents.filter((e) => e.source === "hook.chat.message");
    const viaEvent = newSessionEvents.filter((e) => e.source === "hook.event" && e.type === "chat.message");
    console.error(`chat.message — via named hook: ${viaHook.length}, via event hook: ${viaEvent.length}`);
    expect(viaHook.length).toBeGreaterThan(0);
    expect(viaEvent.length).toBe(0);
  });

  it("tool hooks fire on their own channels, never via the event hook", () => {
    const toolViaEvent = newSessionEvents.filter(
      (e) => e.source === "hook.event" &&
        (e.type === "tool.execute.before" || e.type === "tool.execute.after")
    );
    expect(toolViaEvent.length).toBe(0);
  });

  it("shell.env fires on its own hook, never via the event hook", () => {
    const viaHook = newSessionEvents.filter((e) => e.source === "hook.shell.env");
    const viaEvent = newSessionEvents.filter((e) => e.source === "hook.event" && e.type === "shell.env");
    console.error(`shell.env — via named hook: ${viaHook.length}, via event hook: ${viaEvent.length}`);
    expect(viaHook.length).toBeGreaterThan(0);
    expect(viaEvent.length).toBe(0);
  });

  it("session.created fires BEFORE chat.message (temper new-session detection depends on this)", () => {
    const sessionCreated = eventsOfType("session.created")[0];
    const firstChatMsg = newSessionEvents.find((e) => e.source === "hook.chat.message");
    expect(sessionCreated).toBeDefined();
    expect(firstChatMsg).toBeDefined();
    console.error(`session.created: +${sessionCreated!.t}ms  chat.message: +${firstChatMsg!.t}ms`);
    expect(sessionCreated!.t).toBeLessThan(firstChatMsg!.t);
  });
});

// ---------------------------------------------------------------------------
// Restore snapshot — same session, restarted process
// ---------------------------------------------------------------------------

describe("event recorder — restore snapshot", () => {
  it("event type sequence matches snapshot", () => {
    const sequence = restoredSessionEvents.map((e) => `[${e.source}] ${e.type}`);
    expect(sequence).toMatchSnapshot();
  });

  it("events before first post-restore prompt (spontaneous restore events)", () => {
    const firstChat = restoredSessionEvents.find((e) => e.source === "hook.chat.message");
    const beforePrompt = restoredSessionEvents.filter((e) => e.t < (firstChat?.t ?? 0));
    process.stderr.write(`\nRestore events before first prompt: ${beforePrompt.length}\n`);
    for (const e of beforePrompt) process.stderr.write(`  +${e.t}ms  ${e.type}\n`);
    expect(beforePrompt.map(({ t: _t, ...rest }) => rest)).toMatchSnapshot();
  });

  it("session.updated fires — or does not — before chat.message on restore", () => {
    const firstUpdated = eventsOfType("session.updated", restoredSessionEvents)[0];
    const firstChat = restoredSessionEvents.find((e) => e.source === "hook.chat.message");
    process.stderr.write(`\nRestore: first event type=${restoredSessionEvents[0]?.type ?? "(none)"} t=+${restoredSessionEvents[0]?.t}ms\n`);
    process.stderr.write(`Restore: session.updated t=+${firstUpdated?.t ?? "N/A"}ms  chat.message t=+${firstChat?.t ?? "N/A"}ms\n`);
    // Snapshot rather than assert — the result is the ground truth for FSM design
    expect({
      sessionUpdatedBeforeChat: firstUpdated !== undefined && firstChat !== undefined
        ? firstUpdated.t < firstChat.t
        : null,
      firstEventType: restoredSessionEvents[0]?.type ?? null,
    }).toMatchSnapshot();
  });
});
