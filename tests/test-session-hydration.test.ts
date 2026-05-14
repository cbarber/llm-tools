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
  waitForMessages,
  writeOpencodeConfig,
} from "./harness";

function taskRequests(mock: MockServer) {
  return mock.history.all.filter(
    (e) => !e.request.systemMessage.includes("title generator"),
  );
}

function countMojoInitInjections(mock: MockServer, afterRequestIndex: number): {
  count: number;
  messages: Array<{ reqIndex: number; role: string; content: string }>;
} {
  // Count net-new mojo-init injections after the given request index.
  // Each injection adds one user message to the history; it then appears
  // in all subsequent requests too. A delta approach avoids counting the
  // same injection multiple times as it propagates through history.
  const tasks = taskRequests(mock);
  const found: Array<{ reqIndex: number; role: string; content: string }> = [];
  let prevCount = afterRequestIndex > 0
    ? tasks[afterRequestIndex - 1]?.request.messages.filter(
        (m) => m.role === "user" && m.content.includes("# mojo-init")
      ).length ?? 0
    : 0;
  for (let i = afterRequestIndex; i < tasks.length; i++) {
    const cur = tasks[i].request.messages.filter(
      (m) => m.role === "user" && m.content.includes("# mojo-init")
    );
    if (cur.length > prevCount) {
      for (const m of cur.slice(prevCount)) {
        found.push({ reqIndex: i, role: m.role, content: m.content });
      }
    }
    prevCount = cur.length;
  }
  return { count: found.length, messages: found };
}

// ---------------------------------------------------------------------------
// Suite 1: session restore does not re-inject once:true skills
// ---------------------------------------------------------------------------

describe("temper plugin — firedOnce hydration on restart (synthetic injection)", () => {
  let mock: MockServer;
  let requestCountBeforeRestart: number;

  beforeAll(async () => {
    const mockPort = await findFreePort();
    const ocPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");
    mock.when((req) => req.toolNames.length > 0).reply("Done.");

    const dir = await createFixtureRepo();
    await writeOpencodeConfig(dir, `${mock.url}/v1`);

    let stop = await startOpencode(dir, ocPort);
    const sessionID = await createSession(ocPort, dir);

    await sendPromptAndWait(ocPort, sessionID, "Hello before restart.", mock);
    requestCountBeforeRestart = taskRequests(mock).length;

    stop = await restartOpencode(stop, dir, ocPort);
    await verifySession(ocPort, sessionID);
    await waitForMessages(ocPort, sessionID);

    await sendPromptAndWait(ocPort, sessionID, "Hello after restart.", mock);

    stop();
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }, 180_000);

  afterAll(async () => {
    await mock?.stop();
  });

  it("mojo-init appears exactly once before restart", () => {
    const tasks = taskRequests(mock);
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
    const { count, messages } = countMojoInitInjections(mock, requestCountBeforeRestart);
    if (count > 0) {
      const tasks = taskRequests(mock);
      console.error(`[DIAGNOSTIC] mojo-init appeared ${count} time(s) AFTER restart`);
      for (const m of messages) console.error(`  req[${m.reqIndex}] [${m.role}]: ${m.content.slice(0, 200).replace(/\n/g, "↵")}`);
      for (let i = requestCountBeforeRestart; i < tasks.length; i++) {
        for (const m of tasks[i].request.messages) {
          console.error(`    [${m.role}]${m.content.includes("# mojo-init") ? " *** MOJO-INIT ***" : ""}: ${m.content.slice(0, 100).replace(/\n/g, "↵")}`);
        }
      }
    }
    expect(count).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Suite 2: manual skill tool call suppresses automated injection after restart
// ---------------------------------------------------------------------------

describe("temper plugin — firedOnce hydration on restart (skill tool call)", () => {
  let mock: MockServer;
  let requestCountBeforeRestart: number;

  beforeAll(async () => {
    const mockPort = await findFreePort();
    const ocPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");
    mock.when((req) => req.toolNames.length > 0).replySequence([
      {
        reply: {
          tools: [{ name: "skill", args: { name: "mojo-init" } }],
        },
      },
      { reply: { text: "Done, mojo-init skill loaded." } },
      { reply: { text: "All done." } },
    ]);

    const dir = await createFixtureRepo();
    await writeOpencodeConfig(dir, `${mock.url}/v1`);

    let stop = await startOpencode(dir, ocPort);
    const sessionID = await createSession(ocPort, dir);

    await sendPromptAndWait(ocPort, sessionID, "Load the mojo-init skill.", mock);
    requestCountBeforeRestart = taskRequests(mock).length;

    stop = await restartOpencode(stop, dir, ocPort);
    await verifySession(ocPort, sessionID);
    await waitForMessages(ocPort, sessionID);

    await sendPromptAndWait(ocPort, sessionID, "Hello after restart.", mock);

    stop();
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }, 180_000);

  afterAll(async () => {
    await mock?.stop();
  });

  it("at least one request was made before restart", () => {
    expect(requestCountBeforeRestart).toBeGreaterThan(0);
  });

  it("mojo-init does NOT appear as synthetic injection after restart when skill was tool-called before", () => {
    const { count, messages } = countMojoInitInjections(mock, requestCountBeforeRestart);
    if (count > 0) {
      const tasks = taskRequests(mock);
      console.error(`[DIAGNOSTIC] mojo-init appeared ${count} time(s) AFTER restart`);
      for (const m of messages) console.error(`  req[${m.reqIndex}] [${m.role}]: ${m.content.slice(0, 200).replace(/\n/g, "↵")}`);
      for (let i = 0; i < requestCountBeforeRestart; i++) {
        for (const m of tasks[i].request.messages) {
          const notable = m.content.includes("mojo-init") || m.content.includes("skill");
          console.error(`  pre-restart req[${i}] [${m.role}]${notable ? " ***" : ""}: ${m.content.slice(0, 100).replace(/\n/g, "↵")}`);
        }
      }
    }
    expect(count).toBe(0);
  });
});
