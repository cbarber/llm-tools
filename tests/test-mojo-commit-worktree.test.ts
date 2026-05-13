/**
 * test-mojo-commit-worktree.test.ts
 *
 * Tests for mojo-commit worktree gate and reset-after-commit:
 *
 * 1. mojo-commit fires when edited file is inside the git worktree
 * 2. mojo-commit does NOT fire when edited file is outside the git worktree
 * 3. after git commit reset, mojo-commit re-arms and fires again on next edit
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer } from "llm-mock-server";
import { rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  createFixtureRepo,
  createSession,
  createTempHome,
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

function findMojoCommitAppearances(
  mock: MockServer,
): Array<{ reqIndex: number; role: string; content: string }> {
  const tasks = taskRequests(mock);
  const found: Array<{ reqIndex: number; role: string; content: string }> = [];
  for (let i = 0; i < tasks.length; i++) {
    for (const m of tasks[i].request.messages) {
      if (m.role === "user" && m.content.includes("# mojo-commit")) {
        found.push({ reqIndex: i, role: m.role, content: m.content });
      }
    }
  }
  return found;
}

function logDiagnostics(mock: MockServer, label: string) {
  const tasks = taskRequests(mock);
  console.error(`[DIAGNOSTIC] ${label} — ${tasks.length} task requests total`);
  for (let i = 0; i < tasks.length; i++) {
    const req = tasks[i].request;
    for (const m of req.messages) {
      const isMojoCommit = m.content.includes("# mojo-commit");
      console.error(
        `  req[${i}] [${m.role}]${isMojoCommit ? " *** MOJO-COMMIT ***" : ""}: ${m.content.slice(0, 120).replace(/\n/g, "↵")}`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Shared opencode instance — one process for all suites in this file
// ---------------------------------------------------------------------------

let ocPort: number;
let stopOpencode: () => void;

beforeAll(async () => {
  ocPort = await findFreePort();
  const tempHome = await createTempHome();
  const sharedDir = await createFixtureRepo();
  ({ stop: stopOpencode } = await startOpencode(sharedDir, ocPort, { HOME: tempHome }));
}, 60_000);

afterAll(async () => {
  stopOpencode?.();
});

// ---------------------------------------------------------------------------
// Suite 1: mojo-commit fires when edited file is inside the worktree
// ---------------------------------------------------------------------------

describe("mojo-commit — worktree gate (inside worktree)", () => {
  let mock: MockServer;

  beforeAll(async () => {
    const mockPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");

    const dir = await createFixtureRepo();

    mock.when((req) => req.toolNames.length > 0).replySequence([
      {
        reply: {
          tools: [{
            name: "bash",
            args: {
              command: "git add README.md",
              description: "stage a file inside the worktree",
            },
          }],
        },
      },
      { reply: { text: "Done." } },
    ]);

    await writeOpencodeConfig(dir, `${mock.url}/v1`);
    const stop = await startOpencode(dir, ocPort);

    const sessionID = await createSession(ocPort, dir);
    await sendPromptAndWait(ocPort, sessionID, "Stage the README inside the repo.", mock);

    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }, 90_000);

  afterAll(async () => {
    await mock?.stop();
  });

  it("fires mojo-commit when the edited file is inside the worktree", () => {
    const appearances = findMojoCommitAppearances(mock);
    if (appearances.length === 0) {
      logDiagnostics(mock, "mojo-commit did not fire — expected it to fire for in-worktree edit");
    }
    expect(appearances.length).toBeGreaterThanOrEqual(1);
  });
});

// ---------------------------------------------------------------------------
// Suite 2: mojo-commit does NOT fire when edited file is outside worktree
// ---------------------------------------------------------------------------

describe("mojo-commit — worktree gate (outside worktree)", () => {
  let mock: MockServer;

  beforeAll(async () => {
    const mockPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");

    mock.when((req) => req.toolNames.length > 0).replySequence([
      {
        reply: {
          tools: [{
            name: "edit",
            args: {
              filePath: "/tmp/outside-worktree-test.txt",
              oldString: "old",
              newString: "new",
            },
          }],
        },
      },
      { reply: { text: "Done." } },
    ]);

    await writeFile("/tmp/outside-worktree-test.txt", "old\n");

    const dir = await createFixtureRepo();
    await writeOpencodeConfig(dir, `${mock.url}/v1`);
    const stop = await startOpencode(dir, ocPort);

    const sessionID = await createSession(ocPort, dir);
    await sendPromptAndWait(ocPort, sessionID, "Edit a file outside the repo.", mock);

    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }, 90_000);

  afterAll(async () => {
    await mock?.stop();
  });

  it("does NOT fire mojo-commit when the edited file is outside the worktree", () => {
    const appearances = findMojoCommitAppearances(mock);
    if (appearances.length > 0) {
      logDiagnostics(mock, "mojo-commit fired unexpectedly for out-of-worktree edit");
    }
    expect(appearances.length).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Suite 3: after git commit reset, mojo-commit re-arms and fires again
// ---------------------------------------------------------------------------

describe("mojo-commit — reset after git commit re-arms injection", () => {
  let mock: MockServer;

  beforeAll(async () => {
    const mockPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");

    const dir = await createFixtureRepo();

    mock.when((req) => req.toolNames.length > 0).replySequence([
      {
        reply: {
          tools: [{
            name: "bash",
            args: {
              command: "git add README.md",
              description: "stage to trigger mojo-commit first time",
            },
          }],
        },
      },
      {
        reply: {
          tools: [{
            name: "bash",
            args: {
              command: "git commit --allow-empty -m 'test: worktree reset'",
              description: "commit to trigger mojo-commit reset",
            },
          }],
        },
      },
      {
        reply: {
          tools: [{
            name: "bash",
            args: {
              command: "git add README.md",
              description: "stage again to trigger mojo-commit second time",
            },
          }],
        },
      },
      { reply: { text: "Done." } },
      { reply: { text: "All done." } },
    ]);

    await writeOpencodeConfig(dir, `${mock.url}/v1`);
    const stop = await startOpencode(dir, ocPort);

    const sessionID = await createSession(ocPort, dir);
    await sendPromptAndWait(ocPort, sessionID, "Stage, commit, then stage again.", mock);

    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }, 90_000);

  afterAll(async () => {
    await mock?.stop();
  });

  it("fires mojo-commit at least twice: once before commit, once after reset", () => {
    const appearances = findMojoCommitAppearances(mock);
    if (appearances.length < 2) {
      logDiagnostics(
        mock,
        `mojo-commit appeared ${appearances.length} time(s), expected >= 2`,
      );
    }
    expect(appearances.length).toBeGreaterThanOrEqual(2);
  });
});
