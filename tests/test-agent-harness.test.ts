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
import { execFile, spawn } from "node:child_process";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { createServer } from "node:net";

const execFileAsync = promisify(execFile);

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

async function findFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = createServer();
    srv.listen(0, "127.0.0.1", () => {
      const addr = srv.address() as { port: number };
      srv.close(() => resolve(addr.port));
    });
    srv.on("error", reject);
  });
}

async function waitFor(
  predicate: () => Promise<boolean> | boolean,
  timeoutMs: number,
  label: string,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await new Promise((r) => setTimeout(r, 300));
  }
  throw new Error(`Timed out (${timeoutMs}ms) waiting for: ${label}`);
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

async function createFixtureRepo(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "opencode-harness-"));
  const git = (...args: string[]) => execFileAsync("git", args, { cwd: dir });
  await git("init");
  await git("config", "user.email", "test@example.com");
  await git("config", "user.name", "Test");
  await writeFile(join(dir, "README.md"), "# Test\n");
  // AGENTS.md triggers the git() alias guard: `[[ -f AGENTS.md ]]`
  // Without this, the pre-9a9d417 alias skips the temper call silently.
  await writeFile(join(dir, "AGENTS.md"), "# AGENTS\n");
  await git("add", ".");
  await git("commit", "-m", "init");
  // .beads dir triggers mojo-init's `when: "[[ -d .beads ]]"` guard
  await mkdir(join(dir, ".beads"));
  return dir;
}

async function writeOpencodeConfig(dir: string, mockBaseUrl: string): Promise<void> {
  await writeFile(join(dir, "opencode.json"), JSON.stringify({
    $schema: "https://opencode.ai/config.json",
    share: "disabled",
    plugin: [],           // no external plugins, rely on ~/.config/opencode/plugins/temper.ts
    permission: "allow",  // auto-approve all tool calls (no interactive prompts)
    provider: {
      "llm-mock": {
        npm: "@ai-sdk/openai-compatible",
        name: "LLM Mock",
        options: { baseURL: mockBaseUrl, apiKey: "test" },
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
}

// ---------------------------------------------------------------------------
// opencode server
// ---------------------------------------------------------------------------

async function startOpencode(dir: string, port: number): Promise<() => void> {
  const nixSmithDir = join(import.meta.dir, "..");
  const stderr: Buffer[] = [];

  const proc = spawn(
    "nix",
    [
      "develop", `${nixSmithDir}#opencode`,
      "--command", "bash", "-c",
      `agent-sandbox opencode serve --port ${port}`,
    ],
    {
      cwd: dir,
      env: { ...process.env, OPENCODE_PORT: String(port), AUTO_LAUNCH: "false", ANTHROPIC_API_KEY: "" },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  proc.stderr?.on("data", (d: Buffer) => stderr.push(d));


  await waitFor(async () => {
    try { return (await fetch(`http://127.0.0.1:${port}/session`)).ok; }
    catch { return false; }
  }, 30_000, "opencode serve to start").catch((err) => {
    process.stderr.write("[opencode stderr]\n" + Buffer.concat(stderr).toString() + "\n");
    proc.kill("SIGTERM");
    throw err;
  });

  return () => {
    proc.kill("SIGTERM");
    if (process.env.HARNESS_DEBUG && stderr.length) {
      process.stderr.write(Buffer.concat(stderr).toString());
    }
  };
}

async function createSession(port: number, dir: string): Promise<string> {
  const res = await fetch(`http://127.0.0.1:${port}/session`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ directory: dir }),
  });
  if (!res.ok) throw new Error(`createSession: ${res.status} ${await res.text()}`);
  return ((await res.json()) as { id: string }).id;
}

/**
 * Send prompt and wait for the full multi-turn response to complete.
 *
 * noReply:false returns when opencode finishes streaming the current model
 * turn. After that, tool execution and follow-up model calls happen async.
 * We wait for mock history to stabilize (no new requests for 2s).
 */
async function sendPromptAndWait(
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
      parts: [{ type: "text", text, synthetic: false }],
    }),
  }).then((r) => r.text());

  // Wait for history to stabilize: no new requests for 2 consecutive seconds
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

// ---------------------------------------------------------------------------
// mojo-edit-nudge: fail action blocks the first edit and delivers nudge text
// ---------------------------------------------------------------------------

let nudgeMock: MockServer;
let nudgeHistory: RequestHistory;
let stopNudgeOpencode: () => void;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  nudgeMock = await createMock({ port: mockPort, logLevel: "none" });

  nudgeMock.when((req) => req.toolNames.length === 0).reply("Test session title");

  // Scripted workflow for fail action test:
  //   Turn 1: model calls edit
  //            → mojo-edit-nudge fires on tool.execute.before, throws
  //            → edit is blocked; model receives tool error with nudge content
  //   Turn 2: model calls edit again (retry after seeing nudge)
  //            → mojo-edit-nudge already fired (once:true); edit proceeds
  //   Turn 3: model replies done
  nudgeMock.when((req) => req.toolNames.length > 0).replySequence([
    {
      reply: {
        tools: [{
          name: "edit",
          args: {
            filePath: "/tmp/test.txt",
            oldString: "hello",
            newString: "hello world",
          },
        }],
      },
    },
    {
      reply: {
        tools: [{
          name: "edit",
          args: {
            filePath: "/tmp/test.txt",
            oldString: "hello",
            newString: "hello world",
          },
        }],
      },
    },
    { reply: { text: "Done." } },
    { reply: { text: "All done." } },
  ]);

  const dir = await createFixtureRepo();
  // Create the file the edit tool will target
  await writeFile("/tmp/test.txt", "hello\n");
  await writeOpencodeConfig(dir, `${nudgeMock.url}/v1`);

  stopNudgeOpencode = await startOpencode(dir, ocPort);

  const sessionID = await createSession(ocPort, dir);
  await sendPromptAndWait(ocPort, sessionID, "Update the test file.", nudgeMock);

  nudgeHistory = nudgeMock.history;

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 90_000);

afterAll(async () => {
  stopNudgeOpencode?.();
  await nudgeMock?.stop();
});

describe("temper plugin — mojo-edit-nudge fail action", () => {
  it("delivers nudge content as tool error on first edit", () => {
    // The fail action throws in tool.execute.before, preventing the edit from
    // running. OpenCode delivers the thrown message as the tool result.
    // The second request should have a tool message containing the nudge heading.
    const tasks = nudgeHistory.all.filter(
      (e) => !e.request.systemMessage.includes("title generator")
    );
    expect(tasks.length).toBeGreaterThanOrEqual(2);
    const afterFirstEdit = tasks[1].request.messages;
    const nudgeInToolResult = afterFirstEdit.some(
      (m) => m.role === "tool" && m.content.includes("# mojo-edit-nudge")
    );
    expect(nudgeInToolResult).toBe(true);
  });

  it("does not block the second edit (once:true resets after first fire)", () => {
    // After the nudge fires once, firedOnce prevents it from firing again
    // until a git commit resets it. The second edit must not produce another
    // tool error with nudge content.
    const tasks = nudgeHistory.all.filter(
      (e) => !e.request.systemMessage.includes("title generator")
    );
    expect(tasks.length).toBeGreaterThanOrEqual(3);
    const afterSecondEdit = tasks[2].request.messages;
    const nudgeAgain = afterSecondEdit.some(
      (m) => m.role === "tool" && m.content.includes("# mojo-edit-nudge")
    );
    expect(nudgeAgain).toBe(false);
  });
});
