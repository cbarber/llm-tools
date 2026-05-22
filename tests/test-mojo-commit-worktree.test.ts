/**
 * test-mojo-commit-worktree.test.ts
 *
 * Tests for mojo-commit worktree gate and reset-after-commit:
 *
 * 1. mojo-commit does NOT fire when edited file is outside the git worktree
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer } from "llm-mock-server";
import { rm, writeFile } from "node:fs/promises";
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

function findMojoCommitAppearances(
  mock: MockServer,
): Array<{ role: string; content: string }> {
  const tasks = taskRequests(mock);
  const found: Array<{ role: string; content: string }> = [];
  for (const m of tasks[tasks.length - 1].request.messages) {
    if (m.role === "user" && m.content.includes("# mojo-commit")) {
      found.push({ role: m.role, content: m.content });
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
// Suite 1: mojo-commit does NOT fire when edited file is outside worktree
// ---------------------------------------------------------------------------

describe("mojo-commit — worktree gate (outside worktree)", () => {
  let stopOpencode: () => void;
  let mock: MockServer;

  beforeAll(async () => {
    const ocPort = await findFreePort();
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

    ({ stop: stopOpencode } = await startOpencode(dir, ocPort));
    const sessionID = await createSession(ocPort, dir);
    await sendPromptAndWait(ocPort, sessionID, "Edit a file outside the repo.", mock);

    await rm(dir, { recursive: true, force: true }).catch(() => { });
  }, 90_000);

  afterAll(async () => {
    stopOpencode?.();
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
