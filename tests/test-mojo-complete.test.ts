/**
 * test-mojo-complete.test.ts
 *
 * Tests for mojo-complete skill: once:true fires once per session,
 * resets on git commit/rebase, and never fires when the when-guard fails.
 *
 * When-guard: "git log origin/HEAD..HEAD --oneline 2>/dev/null | grep -q ."
 *   - Exits 1 (false) when no remote exists → mojo-complete never fires.
 *   - Exits 0 (true) when origin/HEAD is set and there are unpushed commits.
 *
 * Fixture variants:
 *   createFixtureRepo()           — no remote, guard always fails
 *   createFixtureRepoWithRemote() — bare local remote, guard passes after
 *                                   an extra commit is added without pushing
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer } from "llm-mock-server";
import { rm, writeFile, mkdir, mkdtemp, readFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import {
  createFixtureRepo,
  createSession,
  findFreePort,
  sendPromptAndWait,
  startOpencode,
  writeOpencodeConfig,
} from "./harness";

const execFileAsync = promisify(execFile);

// ---------------------------------------------------------------------------
// Helper: fixture repo with a local bare remote and one unpushed commit
// so that the mojo-complete when-guard passes.
// ---------------------------------------------------------------------------

async function createFixtureRepoWithRemote(): Promise<string> {
  const base = await mkdtemp(join(tmpdir(), "opencode-harness-remote-"));

  const bareDir = join(base, "remote.git");
  await execFileAsync("git", ["init", "--bare", bareDir]);

  const dir = join(base, "worktree");
  await execFileAsync("git", ["clone", bareDir, dir]);

  const git = (...args: string[]) => execFileAsync("git", args, { cwd: dir });

  await git("config", "user.email", "test@example.com");
  await git("config", "user.name", "Test");

  await writeFile(join(dir, "README.md"), "# Test\n");
  await writeFile(join(dir, "AGENTS.md"), "# AGENTS\n");
  await git("add", ".");
  await git("commit", "-m", "init");
  await git("push", "origin", "main");

  // Set origin/HEAD so "git log origin/HEAD..HEAD" resolves correctly
  await git("remote", "set-head", "origin", "main");

  await mkdir(join(dir, ".beads"));
  await mkdir(join(dir, ".opencode"));

  // Add an unpushed commit so the mojo-complete when-guard passes
  await writeFile(join(dir, "UNPUSHED.md"), "# Unpushed\n");
  await git("add", ".");
  await git("commit", "-m", "unpushed work");

  // Repoint origin to a github.com-shaped URL so setup-agent-api-tokens.sh
  // can extract owner "test" and find the harness token file github-token-test.
  // The actual remote is unreachable; refs are already fetched locally.
  await git("remote", "set-url", "origin", "https://github.com/test/test");

  return dir;
}

function taskRequests(mock: MockServer) {
  return mock.history.all.filter(
    (e) => !e.request.systemMessage.includes("title generator"),
  );
}

function findMojoCompleteAppearancesInFinalMessage(mock: MockServer): Array<{ reqIndex: number; role: string; content: string }> {
  const tasks = taskRequests(mock);
  const last = tasks.length - 1;
  const found: Array<{ reqIndex: number; role: string; content: string }> = [];
  for (const m of tasks[last].request.messages) {
    if (m.role === "user" && m.content.includes("# mojo-complete")) {
      found.push({ reqIndex: last, role: m.role, content: m.content });
    }
  }
  return found;
}

function logDiagnostics(mock: MockServer, label: string) {
  const tasks = taskRequests(mock);
  console.error(`[DIAGNOSTIC] ${label} — ${tasks.length} task requests total`);
  for (let i = 0; i < tasks.length; i++) {
    for (const m of tasks[i].request.messages) {
      const isMojoComplete = m.content.includes("# mojo-complete");
      console.error(
        `  req[${i}] [${m.role}]${isMojoComplete ? " *** MOJO-COMPLETE ***" : ""}: ${m.content.slice(0, 120).replace(/\n/g, "↵")}`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Suite 1: when-guard fails (no remote) — mojo-complete never fires
// ---------------------------------------------------------------------------

describe("mojo-complete — when-guard fails (no remote)", () => {
  let stopOpencode: () => void;
  let mock: MockServer;

  beforeAll(async () => {
    const mockPort = await findFreePort();
    const ocPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");
    mock.when((req) => req.toolNames.length > 0).replySequence([
      { reply: { text: "Done after first prompt." } },
      { reply: { text: "Done after second prompt." } },
    ]);

    const dir = await createFixtureRepo();
    await writeOpencodeConfig(dir, `${mock.url}/v1`);

    ({ stop: stopOpencode } = await startOpencode(dir, ocPort));
    const sessionID = await createSession(ocPort, dir);

    await sendPromptAndWait(ocPort, sessionID, "First prompt.", mock);
    await sendPromptAndWait(ocPort, sessionID, "Second prompt.", mock);

    await rm(dir, { recursive: true, force: true }).catch(() => { });
  }, 90_000);

  afterAll(async () => {
    stopOpencode?.();
    await mock?.stop();
  });

  it("never fires across multiple idle events", () => {
    const appearances = findMojoCompleteAppearancesInFinalMessage(mock);
    if (appearances.length > 0) {
      logDiagnostics(mock, "mojo-complete appeared unexpectedly");
    }
    expect(appearances.length).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Suite 2: once:true — fires exactly once when guard passes
// ---------------------------------------------------------------------------

describe("mojo-complete — once:true fires at most once per session", () => {
  let stopOpencode: () => void;
  let mock: MockServer;

  beforeAll(async () => {
    const mockPort = await findFreePort();
    const ocPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");
    mock.when((req) => req.toolNames.length > 0).replySequence([
      { reply: { text: "Done after first prompt." } },
      { reply: { text: "Done after second prompt." } },
    ]);

    const dir = await createFixtureRepoWithRemote();
    await writeOpencodeConfig(dir, `${mock.url}/v1`);

    ({ stop: stopOpencode } = await startOpencode(dir, ocPort));
    const sessionID = await createSession(ocPort, dir);

    await sendPromptAndWait(ocPort, sessionID, "First prompt.", mock);
    await new Promise((r) => setTimeout(r, 1000));
    await sendPromptAndWait(ocPort, sessionID, "Second prompt.", mock);

    await rm(dir, { recursive: true, force: true }).catch(() => { });
  }, 90_000);

  afterAll(async () => {
    stopOpencode?.();
    await mock?.stop();
  });

  it("fires exactly once despite multiple session.idle events", () => {
    const appearances = findMojoCompleteAppearancesInFinalMessage(mock);
    if (appearances.length !== 1) {
      logDiagnostics(mock, `mojo-complete appeared ${appearances.length} time(s), expected 1`);
    }
    expect(appearances.length).toBe(1);
  });
});
