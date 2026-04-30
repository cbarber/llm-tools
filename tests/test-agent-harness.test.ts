/**
 * test-agent-harness.test.ts
 *
 * End-to-end tests for the opencode + temper plugin stack using bun test.
 *
 * Starts opencode in server mode against llm-mock-server (in-process), sends
 * a scripted prompt, and asserts on what arrives at the model API boundary.
 *
 * Primary regression: mojo-commit double-fire (fixed in commit 9a9d417).
 * Before that fix, the git() bash alias also called `temper commit`, causing
 * a second injection alongside the one from temper.ts. Reverting 9a9d417
 * causes the mojo-commit assertion to fail.
 *
 * Usage:
 *   cd tools && bun test test-agent-harness.test.ts
 *
 * Requires opencode in PATH (nix develop .#opencode).
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer, RequestHistory } from "llm-mock-server";
import { rm } from "node:fs/promises";
import { createFixtureRepo, createSession, findFreePort, sendPromptAndWait, startOpencode, writeOpencodeConfig } from "./harness"

// ---------------------------------------------------------------------------
// Shared test state — set up once for all tests in the suite
// ---------------------------------------------------------------------------

function taskRequests(history: RequestHistory) {
  return history.all.filter(
    (e) => !e.request.systemMessage.includes("title generator")
  );
}

let mock: MockServer;
let stopOpencode: () => void;
let history: RequestHistory;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  mock = await createMock({ port: mockPort, logLevel: "none" });

  // Title generator requests have no tools — return a title and move on
  mock.when((req) => req.toolNames.length === 0).reply("Test session title");

  // Task requests: scripted three-turn workflow
  //   Turn 1: model calls todowrite (mark task in_progress)
  //   Turn 2: model calls bash with git add + git commit
  //            → triggers mojo-commit via tool.execute.after
  //   Turn 3: model replies with plain text (done)
  mock.when((req) => req.toolNames.length > 0).replySequence([
    {
      reply: {
        tools: [{
          name: "todowrite",
          args: {
            todos: [{ id: "1", content: "Update README.md", status: "in_progress", priority: "high" }],
          },
        }],
      },
    },
    {
      reply: {
        tools: [{
          name: "bash",
          args: {
            command: "git add . && git commit -m 'test: update readme'",
            description: "Stage and commit changes",
          },
        }],
      },
    },
    { reply: { text: "Done. The changes have been committed." } },
    { reply: { text: "All done." } }, // fallback for retries
  ]);

  const dir = await createFixtureRepo();
  await writeOpencodeConfig(dir, `${mock.url}/v1`);

  stopOpencode = await startOpencode(dir, ocPort);

  const sessionID = await createSession(ocPort, dir);
  await sendPromptAndWait(
    ocPort,
    sessionID,
    "Update README.md with a description and commit the change.",
    mock,
  );

  history = mock.history;

  if (process.env.HARNESS_DEBUG) {
    for (const [i, e] of history.all.entries()) {
      console.log(`REQ ${i}: ${e.request.messages.length} msgs, tools: ${e.request.toolNames.length}`);
      for (const m of e.request.messages)
        console.log(`  [${m.role}] ${m.content.slice(0, 120).replace(/\n/g, "↵")}`);
    }
  }

  await rm(dir, { recursive: true, force: true }).catch(err => console.error("Failed to clean up", err));
}, 90_000);

afterAll(async () => {
  stopOpencode?.();
  await mock?.stop();
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("temper plugin — mojo-init", () => {
  it("injects exactly once on session.created", () => {
    const tasks = taskRequests(history);
    expect(tasks.length).toBeGreaterThanOrEqual(1);

    const count = tasks[0].request.messages.filter(
      (m) => m.role === "user" && m.content.includes("# mojo-init")
    ).length;
    expect(count).toBe(1);
  });
});

describe("temper plugin — mojo-commit (9a9d417 regression)", () => {
  it("injects exactly once as a synthetic user message after git commit", () => {
    const tasks = taskRequests(history);
    expect(tasks.length).toBeGreaterThanOrEqual(2);

    let syntheticCount = 0;
    for (let i = 1; i < tasks.length; i++) {
      for (const m of tasks[i].request.messages) {
        if (m.role === "user" && m.content.includes("# mojo-commit")) syntheticCount++;
      }
    }
    expect(syntheticCount).toBe(1);
  });

  it("does not appear in tool result messages (pre-9a9d417 alias double-fire)", () => {
    // The pre-fix git() alias called `temper commit`, whose stdout was captured
    // as the bash tool result. That output starts with "📋 Commit Format:" —
    // the header printed by the temper CLI before the skill body.
    // Post-fix: only temper.ts injects the skill as a synthetic user message.
    const tasks = taskRequests(history);
    expect(tasks.length).toBeGreaterThanOrEqual(2);

    let aliasInToolResult = 0;
    for (let i = 1; i < tasks.length; i++) {
      for (const m of tasks[i].request.messages) {
        if (m.role === "tool" && m.content.includes("📋 Commit Format:")) aliasInToolResult++;
      }
    }
    expect(aliasInToolResult).toBe(0);
  });
});

describe("temper plugin — regex fix (todowrite must not trigger mojo-commit)", () => {
  it("does not inject mojo-commit after a todowrite tool call", () => {
    // Before anchoring to ^(edit|write)$, "edit|write" matched "todowrite"
    // as a substring, causing mojo-commit to inject on every todo update.
    // Turn 1 is todowrite; Turn 2 is the request after it completes.
    // mojo-commit must not appear in Turn 2's messages.
    const tasks = taskRequests(history);
    expect(tasks.length).toBeGreaterThanOrEqual(2);
    const afterTodowrite = tasks[1].request.messages;
    const hasMojoCommitAfterTodowrite = afterTodowrite.some(
      (m) => m.role === "user" && m.content.includes("# mojo-commit")
    );
    expect(hasMojoCommitAfterTodowrite).toBe(false);
  });
});
