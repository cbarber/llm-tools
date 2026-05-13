/**
 * test-session-hydration.test.ts
 *
 * Verifies that the temper plugin hydrates firedOnce from session history when
 * OpenCode restarts mid-session, preventing once:true skills (e.g. mojo-init)
 * from re-injecting after a process restart.
 *
 * Tests:
 *   1. session restore does not re-inject once:true skills
 *   2. manual skill tool call suppresses automated injection after restart
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer } from "llm-mock-server";
import { rm } from "node:fs/promises";
import {
  createFixtureRepo,
  createSession,
  findFreePort,
  restartOpencode,
  sendPromptAndWait,
  startOpencode,
  verifySession,
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

function countMojoInitInjections(mock: MockServer, afterRequestIndex: number): {
  count: number;
  messages: Array<{ reqIndex: number; role: string; content: string }>;
} {
  const tasks = taskRequests(mock);
  const found: Array<{ reqIndex: number; role: string; content: string }> = [];
  for (let i = afterRequestIndex; i < tasks.length; i++) {
    for (const m of tasks[i].request.messages) {
      if (m.role === "user" && m.content.includes("# mojo-init")) {
        found.push({ reqIndex: i, role: m.role, content: m.content });
      }
    }
  }
  return { count: found.length, messages: found };
}

// ---------------------------------------------------------------------------
// Test 2: session restore does not re-inject once:true skills
// ---------------------------------------------------------------------------

let restoreMock: MockServer;
let stopRestoreOpencode: () => void;
let restoreSessionID: string;
let requestCountBeforeRestart: number;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  restoreMock = await createMock({ port: mockPort, logLevel: "none" });
  restoreMock.when((req) => req.toolNames.length === 0).reply("Test session title");
  restoreMock.when((req) => req.toolNames.length > 0).reply("Done.");

  const dir = await createFixtureRepo();
  await writeOpencodeConfig(dir, `${restoreMock.url}/v1`);

  stopRestoreOpencode = await startOpencode(dir, ocPort);
  restoreSessionID = await createSession(ocPort, dir);

  await sendPromptAndWait(ocPort, restoreSessionID, "Hello before restart.", restoreMock);
  requestCountBeforeRestart = taskRequests(restoreMock).length;

  stopRestoreOpencode = await restartOpencode(stopRestoreOpencode, dir, ocPort);
  await verifySession(ocPort, restoreSessionID);

  await sendPromptAndWait(ocPort, restoreSessionID, "Hello after restart.", restoreMock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 180_000);

afterAll(async () => {
  stopRestoreOpencode?.();
  await restoreMock?.stop();
});

describe("temper plugin — firedOnce hydration on restart (synthetic injection)", () => {
  it("mojo-init appears exactly once before restart", () => {
    const tasks = taskRequests(restoreMock);
    expect(tasks.length).toBeGreaterThan(0);
    let found = 0;
    for (let i = 0; i < requestCountBeforeRestart; i++) {
      for (const m of tasks[i].request.messages) {
        if (m.role === "user" && m.content.includes("# mojo-init")) found++;
      }
    }
    if (found !== 1) {
      console.error(`[DIAGNOSTIC] mojo-init count before restart: ${found}`);
      for (let i = 0; i < requestCountBeforeRestart; i++) {
        console.error(`  req[${i}]:`, tasks[i].request.messages.map((m) => `[${m.role}] ${m.content.slice(0, 80).replace(/\n/g, "↵")}`));
      }
    }
    expect(found).toBe(1);
  });

  it("mojo-init does NOT re-appear in requests after restart", () => {
    const { count, messages } = countMojoInitInjections(restoreMock, requestCountBeforeRestart);
    if (count > 0) {
      const tasks = taskRequests(restoreMock);
      console.error(`[DIAGNOSTIC] mojo-init appeared ${count} time(s) AFTER restart`);
      console.error(`[DIAGNOSTIC] requestCountBeforeRestart: ${requestCountBeforeRestart}`);
      console.error(`[DIAGNOSTIC] total task requests: ${tasks.length}`);
      for (const m of messages) {
        console.error(`  req[${m.reqIndex}] [${m.role}]: ${m.content.slice(0, 200).replace(/\n/g, "↵")}`);
      }
      for (let i = requestCountBeforeRestart; i < tasks.length; i++) {
        console.error(`  req[${i}]:`);
        for (const m of tasks[i].request.messages) {
          const hasMojoInit = m.content.includes("# mojo-init");
          console.error(`    [${m.role}]${hasMojoInit ? " *** MOJO-INIT ***" : ""}: ${m.content.slice(0, 100).replace(/\n/g, "↵")}`);
        }
      }
    }
    expect(count).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Test 3: manual skill tool call suppresses automated injection after restart
// ---------------------------------------------------------------------------

let toolCallMock: MockServer;
let stopToolCallOpencode: () => void;
let toolCallSessionID: string;
let toolCallRequestCountBeforeRestart: number;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  toolCallMock = await createMock({ port: mockPort, logLevel: "none" });
  toolCallMock.when((req) => req.toolNames.length === 0).reply("Test session title");
  toolCallMock.when((req) => req.toolNames.length > 0).replySequence([
    {
      reply: {
        tools: [{ name: "skill", args: { name: "mojo-init" } }],
      },
    },
    { reply: { text: "Done, mojo-init skill loaded." } },
    { reply: { text: "All done." } },
  ]);

  const dir = await createFixtureRepo();
  await writeOpencodeConfig(dir, `${toolCallMock.url}/v1`);

  stopToolCallOpencode = await startOpencode(dir, ocPort);
  toolCallSessionID = await createSession(ocPort, dir);

  await sendPromptAndWait(ocPort, toolCallSessionID, "Load the mojo-init skill.", toolCallMock);
  toolCallRequestCountBeforeRestart = taskRequests(toolCallMock).length;

  stopToolCallOpencode = await restartOpencode(stopToolCallOpencode, dir, ocPort);
  await verifySession(ocPort, toolCallSessionID);

  await sendPromptAndWait(ocPort, toolCallSessionID, "Hello after restart.", toolCallMock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 180_000);

afterAll(async () => {
  stopToolCallOpencode?.();
  await toolCallMock?.stop();
});

describe("temper plugin — firedOnce hydration on restart (skill tool call)", () => {
  it("at least one request was made before restart", () => {
    expect(toolCallRequestCountBeforeRestart).toBeGreaterThan(0);
  });

  it("mojo-init does NOT appear as synthetic user message after restart when skill was tool-called before", () => {
    const { count, messages } = countMojoInitInjections(toolCallMock, toolCallRequestCountBeforeRestart);
    if (count > 0) {
      const tasks = taskRequests(toolCallMock);
      console.error(`[DIAGNOSTIC] mojo-init appeared ${count} time(s) as synthetic injection AFTER restart`);
      console.error(`[DIAGNOSTIC] toolCallRequestCountBeforeRestart: ${toolCallRequestCountBeforeRestart}`);
      console.error(`[DIAGNOSTIC] total task requests: ${tasks.length}`);
      for (const m of messages) {
        console.error(`  req[${m.reqIndex}] [${m.role}]: ${m.content.slice(0, 200).replace(/\n/g, "↵")}`);
      }
      console.error(`[DIAGNOSTIC] messages before restart (hydration source):`);
      for (let i = 0; i < toolCallRequestCountBeforeRestart; i++) {
        for (const m of tasks[i].request.messages) {
          const notable = m.content.includes("mojo-init") || m.content.includes("skill");
          console.error(`  req[${i}] [${m.role}]${notable ? " ***" : ""}: ${m.content.slice(0, 100).replace(/\n/g, "↵")}`);
        }
      }
    }
    expect(count).toBe(0);
  });
});
