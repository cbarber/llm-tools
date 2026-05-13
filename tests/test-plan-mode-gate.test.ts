/**
 * test-plan-mode-gate.test.ts
 *
 * Verifies that the temper plugin suppresses skill injections when the session
 * is in plan mode (last assistant message has agent === "plan").
 *
 * ## Plan-mode detection
 *
 * OpenCode routes prompts to different agents based on the `agent` field in
 * the prompt body (POST /session/{id}/message). When `agent: "plan"` is
 * specified, the resulting AssistantMessage has `agent: "plan"`. The temper
 * plugin tracks `lastAssistantAgent` via:
 *   1. Hydration: scanning message history on session restore
 *   2. Streaming: `message.updated` events from the v1 Event stream
 *
 * ## SDK findings
 *
 * - `AssistantMessage.mode` holds "primary" | "subagent" | "all" (agent config
 *   mode), NOT plan mode. The task spec says `mode === "plan"` but this is
 *   incorrect — mode never equals "plan".
 * - Plan mode is indicated by `AssistantMessage.agent === "plan"`.
 * - `agent` is present in v2 AssistantMessage types. The live data includes
 *   it since the server emits v2-shaped data even through the v1 event stream.
 * - `EventMessageUpdated` is in BOTH v1 and v2 Event unions.
 * - v1 EventMessageUpdated.properties has only `{ info: Message }` (no sessionID).
 *   sessionID must be read from `info.sessionID`.
 * - The plugin event hook uses the v1 Event type, but real data includes
 *   the agent field since OpenCode 1.14+ always emits v2-shaped messages.
 *
 * ## Plan-mode triggering
 *
 * Plan mode CAN be triggered via the API: POST /session/{id}/message with
 * `agent: "plan"` in the body routes to the plan agent. The resulting
 * AssistantMessage has `agent: "plan"`.
 *
 * Tests:
 *   1. Skills are suppressed when lastAssistantAgent === "plan"
 *   2. Skills fire normally in non-plan mode (baseline)
 *   3. Skills resume after plan → build transition
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer } from "llm-mock-server";
import { rm } from "node:fs/promises";
import {
  createFixtureRepo,
  createSession,
  findFreePort,
  sendPromptAndWait,
  startOpencode,
  writeOpencodeConfig,
} from "./harness";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function taskRequests(mock: MockServer) {
  return mock.history.all.filter(
    (e) => !e.request.systemMessage.includes("title generator"),
  );
}

function countInjections(mock: MockServer, skillHeader: string): number {
  let count = 0;
  for (const e of taskRequests(mock)) {
    for (const m of e.request.messages) {
      if (m.role === "user" && m.content.includes(skillHeader)) count++;
    }
  }
  return count;
}

function logDiagnostics(mock: MockServer, label: string) {
  const tasks = taskRequests(mock);
  console.error(`[DIAGNOSTIC] ${label} — ${tasks.length} task requests total`);
  for (let i = 0; i < tasks.length; i++) {
    for (const m of tasks[i].request.messages) {
      const notable = m.content.includes("# mojo-commit") || m.content.includes("# mojo-init");
      console.error(
        `  req[${i}] [${m.role}]${notable ? " ***" : ""}: ${m.content.slice(0, 120).replace(/\n/g, "↵")}`,
      );
    }
  }
}

/**
 * Send prompt with agent=plan and wait for stabilization.
 * The plan agent does not call edit tools, so it replies with plain text.
 */
async function sendPlanPromptAndWait(
  port: number,
  sessionID: string,
  text: string,
  mock: MockServer,
): Promise<void> {
  await fetch(`http://127.0.0.1:${port}/session/${sessionID}/message`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      noReply: false,
      agent: "plan",
      parts: [{ type: "text", text, synthetic: false }],
    }),
  }).then((r) => r.text());

  // Wait for history to stabilize
  let lastCount = mock.history.count();
  let stableFor = 0;
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 500));
    const count = mock.history.count();
    if (count === lastCount) {
      stableFor += 500;
      if (stableFor >= 2_000) break;
    } else {
      lastCount = count;
      stableFor = 0;
    }
  }
}

// ---------------------------------------------------------------------------
// Test suite 1: mojo-commit suppressed in plan mode
// ---------------------------------------------------------------------------

let planGateMock: MockServer;
let stopPlanGateOpencode: () => void;
let planGateRequestCountAfterPlan: number;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  planGateMock = await createMock({ port: mockPort, logLevel: "none" });
  planGateMock.when((req) => req.toolNames.length === 0).reply("Test session title");
  planGateMock.when((req) => req.toolNames.length > 0).replySequence([
    {
      reply: {
        tools: [{
          name: "bash",
          args: {
            command: "git add . && git commit -m 'test: plan gate'",
            description: "commit in plan mode context",
          },
        }],
      },
    },
    { reply: { text: "Done." } },
    { reply: { text: "All done." } },
  ]);

  const dir = await createFixtureRepo();
  await writeOpencodeConfig(dir, `${planGateMock.url}/v1`);

  stopPlanGateOpencode = await startOpencode(dir, ocPort);
  const sessionID = await createSession(ocPort, dir);

  // Step 1: Send a plan-mode prompt to set lastAssistantAgent = "plan"
  await sendPlanPromptAndWait(ocPort, sessionID, "Draft a plan for the work.", planGateMock);
  planGateRequestCountAfterPlan = taskRequests(planGateMock).length;

  // Step 2: Send a build-mode prompt that triggers a git commit
  // mojo-commit should be suppressed due to plan gate
  await sendPromptAndWait(ocPort, sessionID, "Commit the current changes.", planGateMock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 120_000);

afterAll(async () => {
  stopPlanGateOpencode?.();
  await planGateMock?.stop();
});

describe("temper plugin — plan-mode gate: mojo-commit suppressed", () => {
  it("recorded requests after plan prompt", () => {
    expect(planGateRequestCountAfterPlan).toBeGreaterThan(0);
  });

  it("mojo-commit does NOT appear in requests after plan-mode response", () => {
    const tasks = taskRequests(planGateMock);
    let count = 0;
    for (let i = planGateRequestCountAfterPlan; i < tasks.length; i++) {
      for (const m of tasks[i].request.messages) {
        if (m.role === "user" && m.content.includes("# mojo-commit")) count++;
      }
    }
    if (count > 0) {
      logDiagnostics(planGateMock, `mojo-commit appeared ${count} time(s) despite plan gate`);
    }
    expect(count).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Test suite 2: mojo-commit fires normally in non-plan (build) mode (baseline)
// ---------------------------------------------------------------------------

let baselineMock: MockServer;
let stopBaselineOpencode: () => void;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  baselineMock = await createMock({ port: mockPort, logLevel: "none" });
  baselineMock.when((req) => req.toolNames.length === 0).reply("Test session title");
  baselineMock.when((req) => req.toolNames.length > 0).replySequence([
    {
      reply: {
        tools: [{
          name: "bash",
          args: {
            command: "git add . && git commit -m 'test: baseline'",
            description: "commit to trigger mojo-commit",
          },
        }],
      },
    },
    { reply: { text: "Done." } },
    { reply: { text: "All done." } },
  ]);

  const dir = await createFixtureRepo();
  await writeOpencodeConfig(dir, `${baselineMock.url}/v1`);

  stopBaselineOpencode = await startOpencode(dir, ocPort);
  const sessionID = await createSession(ocPort, dir);

  await sendPromptAndWait(ocPort, sessionID, "Commit the current changes.", baselineMock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 120_000);

afterAll(async () => {
  stopBaselineOpencode?.();
  await baselineMock?.stop();
});

describe("temper plugin — plan-mode gate: baseline (build mode fires normally)", () => {
  it("mojo-commit appears at least once in normal build mode", () => {
    const count = countInjections(baselineMock, "# mojo-commit");
    if (count === 0) {
      logDiagnostics(baselineMock, "mojo-commit did not appear in build mode");
    }
    expect(count).toBeGreaterThanOrEqual(1);
  });
});

// ---------------------------------------------------------------------------
// Test suite 3: plan → build transition resumes injections
// ---------------------------------------------------------------------------

let transitionMock: MockServer;
let stopTransitionOpencode: () => void;
let transitionCountAfterPlan: number;
let transitionCountAfterFirstBuild: number;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  transitionMock = await createMock({ port: mockPort, logLevel: "none" });
  transitionMock.when((req) => req.toolNames.length === 0).reply("Test session title");
  transitionMock.when((req) => req.toolNames.length > 0).replySequence([
    // Build prompt 1: git commit — suppressed by plan gate
    {
      reply: {
        tools: [{
          name: "bash",
          args: {
            command: "git add . && git commit -m 'first commit'",
            description: "first commit in build after plan",
          },
        }],
      },
    },
    { reply: { text: "First commit done." } },
    // Build prompt 2: git commit — should fire now (plan gate lifted)
    {
      reply: {
        tools: [{
          name: "bash",
          args: {
            command: "git commit --allow-empty -m 'second commit'",
            description: "second commit — should trigger mojo-commit",
          },
        }],
      },
    },
    { reply: { text: "Second commit done." } },
    { reply: { text: "All done." } },
  ]);

  const dir = await createFixtureRepo();
  await writeOpencodeConfig(dir, `${transitionMock.url}/v1`);

  stopTransitionOpencode = await startOpencode(dir, ocPort);
  const sessionID = await createSession(ocPort, dir);

  // Step 1: Plan-mode prompt
  await sendPlanPromptAndWait(ocPort, sessionID, "Plan the work.", transitionMock);
  transitionCountAfterPlan = taskRequests(transitionMock).length;

  // Step 2: Build-mode prompt with commit — suppressed by plan gate
  await sendPromptAndWait(ocPort, sessionID, "Commit the first change.", transitionMock);
  transitionCountAfterFirstBuild = taskRequests(transitionMock).length;

  // Step 3: Another build-mode prompt with commit — should fire now
  await sendPromptAndWait(ocPort, sessionID, "Commit the second change.", transitionMock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 150_000);

afterAll(async () => {
  stopTransitionOpencode?.();
  await transitionMock?.stop();
});

describe("temper plugin — plan-mode gate: plan→build transition", () => {
  it("mojo-commit is suppressed immediately after plan-mode response", () => {
    const tasks = taskRequests(transitionMock);
    let count = 0;
    for (let i = transitionCountAfterPlan; i < transitionCountAfterFirstBuild; i++) {
      for (const m of tasks[i].request.messages) {
        if (m.role === "user" && m.content.includes("# mojo-commit")) count++;
      }
    }
    if (count > 0) {
      logDiagnostics(transitionMock, `mojo-commit appeared ${count} time(s) in first build after plan`);
    }
    expect(count).toBe(0);
  });

  it("mojo-commit fires in second build prompt (plan gate lifted)", () => {
    const tasks = taskRequests(transitionMock);
    let count = 0;
    for (let i = transitionCountAfterFirstBuild; i < tasks.length; i++) {
      for (const m of tasks[i].request.messages) {
        if (m.role === "user" && m.content.includes("# mojo-commit")) count++;
      }
    }
    if (count === 0) {
      logDiagnostics(transitionMock, "mojo-commit did not fire after plan→build transition");
    }
    expect(count).toBeGreaterThanOrEqual(1);
  });
});
