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
import { rm, writeFile, mkdir, mkdtemp } from "node:fs/promises";
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

  return dir;
}

function taskRequests(mock: MockServer) {
  return mock.history.all.filter(
    (e) => !e.request.systemMessage.includes("title generator"),
  );
}

function findMojoCompleteAppearances(mock: MockServer): Array<{ reqIndex: number; role: string; content: string }> {
  const tasks = taskRequests(mock);
  const found: Array<{ reqIndex: number; role: string; content: string }> = [];
  for (let i = 0; i < tasks.length; i++) {
    for (const m of tasks[i].request.messages) {
      if (m.role === "user" && m.content.includes("# mojo-complete")) {
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
    for (const m of tasks[i].request.messages) {
      const isMojoComplete = m.content.includes("# mojo-complete");
      console.error(
        `  req[${i}] [${m.role}]${isMojoComplete ? " *** MOJO-COMPLETE ***" : ""}: ${m.content.slice(0, 120).replace(/\n/g, "↵")}`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Test suite 1: when-guard fails (no remote) — mojo-complete never fires
// ---------------------------------------------------------------------------

let noRemoteMock: MockServer;
let stopNoRemoteOpencode: () => void;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  noRemoteMock = await createMock({ port: mockPort, logLevel: "none" });
  noRemoteMock.when((req) => req.toolNames.length === 0).reply("Test session title");
  noRemoteMock.when((req) => req.toolNames.length > 0).replySequence([
    { reply: { text: "Done after first prompt." } },
    { reply: { text: "Done after second prompt." } },
    { reply: { text: "Done after third prompt." } },
  ]);

  const dir = await createFixtureRepo();
  await writeOpencodeConfig(dir, `${noRemoteMock.url}/v1`);

  stopNoRemoteOpencode = await startOpencode(dir, ocPort);
  const sessionID = await createSession(ocPort, dir);

  await sendPromptAndWait(ocPort, sessionID, "First prompt.", noRemoteMock);
  await sendPromptAndWait(ocPort, sessionID, "Second prompt.", noRemoteMock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 90_000);

afterAll(async () => {
  stopNoRemoteOpencode?.();
  await noRemoteMock?.stop();
});

describe("mojo-complete — when-guard fails (no remote)", () => {
  it("never fires across multiple idle events", () => {
    const appearances = findMojoCompleteAppearances(noRemoteMock);
    if (appearances.length > 0) {
      logDiagnostics(noRemoteMock, "mojo-complete appeared unexpectedly");
    }
    expect(appearances.length).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Test suite 2: once:true — fires exactly once when guard passes
// ---------------------------------------------------------------------------

let onceMock: MockServer;
let stopOnceOpencode: () => void;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  onceMock = await createMock({ port: mockPort, logLevel: "none" });
  onceMock.when((req) => req.toolNames.length === 0).reply("Test session title");
  onceMock.when((req) => req.toolNames.length > 0).replySequence([
    { reply: { text: "Done after first prompt." } },
    { reply: { text: "Done after second prompt." } },
    { reply: { text: "Done after third prompt." } },
  ]);

  const dir = await createFixtureRepoWithRemote();
  await writeOpencodeConfig(dir, `${onceMock.url}/v1`);

  stopOnceOpencode = await startOpencode(dir, ocPort);
  const sessionID = await createSession(ocPort, dir);

  // Multiple prompts → multiple session.idle events; once:true must cap at one injection
  await sendPromptAndWait(ocPort, sessionID, "First prompt.", onceMock);
  await sendPromptAndWait(ocPort, sessionID, "Second prompt.", onceMock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 90_000);

afterAll(async () => {
  stopOnceOpencode?.();
  await onceMock?.stop();
});

describe("mojo-complete — once:true fires at most once per session", () => {
  it("fires exactly once despite multiple session.idle events", () => {
    const appearances = findMojoCompleteAppearances(onceMock);
    if (appearances.length !== 1) {
      logDiagnostics(onceMock, `mojo-complete appeared ${appearances.length} time(s), expected 1`);
    }
    expect(appearances.length).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Test suite 3: reset on git commit lets mojo-complete fire again
// ---------------------------------------------------------------------------

let resetMock: MockServer;
let stopResetOpencode: () => void;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  resetMock = await createMock({ port: mockPort, logLevel: "none" });
  resetMock.when((req) => req.toolNames.length === 0).reply("Test session title");

  // Scripted workflow:
  //   Prompt 1 / Turn 1: model replies Done → session.idle fires → mojo-complete injects
  //   Prompt 2 / Turn 2: model calls bash git commit → tool.execute.after fires → action:reset
  //   Prompt 2 / Turn 3: model replies Done → session.idle fires → mojo-complete injects again
  resetMock.when((req) => req.toolNames.length > 0).replySequence([
    { reply: { text: "Done after first prompt." } },
    {
      reply: {
        tools: [{
          name: "bash",
          args: {
            command: "git commit --allow-empty -m 'test reset'",
            description: "commit to trigger reset",
          },
        }],
      },
    },
    { reply: { text: "Done after commit." } },
    { reply: { text: "All done." } },
  ]);

  const dir = await createFixtureRepoWithRemote();
  await writeOpencodeConfig(dir, `${resetMock.url}/v1`);

  stopResetOpencode = await startOpencode(dir, ocPort);
  const sessionID = await createSession(ocPort, dir);

  await sendPromptAndWait(ocPort, sessionID, "First prompt before commit.", resetMock);
  await sendPromptAndWait(ocPort, sessionID, "Second prompt: please commit.", resetMock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 90_000);

afterAll(async () => {
  stopResetOpencode?.();
  await resetMock?.stop();
});

describe("mojo-complete — reset on git commit allows re-fire", () => {
  it("fires twice total: once before commit, once after reset", () => {
    const appearances = findMojoCompleteAppearances(resetMock);
    if (appearances.length !== 2) {
      logDiagnostics(resetMock, `mojo-complete appeared ${appearances.length} time(s), expected 2`);
    }
    expect(appearances.length).toBe(2);
  });
});
