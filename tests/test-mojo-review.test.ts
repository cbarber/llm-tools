/**
 * test-mojo-review.test.ts
 *
 * The mojo-review reviewer entry's initialization shows the checkout under
 * review and its worktrees, including proposal worktrees, without failing
 * the skill load outside a repository.
 */

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const root = join(import.meta.dir, "..");

let dir: string;
let env: NodeJS.ProcessEnv;

async function sh(cwd: string, cmd: string, ...args: string[]): Promise<string> {
  return (await execFileAsync(cmd, args, { cwd, env })).stdout;
}

// Only the initialization output, which temper prints before the body.
async function render(cwd: string): Promise<string> {
  const out = await sh(cwd, "bash", join(root, "tools", "temper"), "mojo-review");
  return out.slice(0, out.indexOf("# mojo-review"));
}

beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), "mojo-review-"));
  const home = join(dir, "home");
  await mkdir(join(home, ".agents", "skills"), { recursive: true });
  await cp(join(root, "agents", "skills", "mojo-review"), join(home, ".agents", "skills", "mojo-review"), {
    recursive: true,
  });
  env = {
    ...process.env,
    HOME: home,
    GIT_AUTHOR_NAME: "t",
    GIT_AUTHOR_EMAIL: "t@example.com",
    GIT_COMMITTER_NAME: "t",
    GIT_COMMITTER_EMAIL: "t@example.com",
  };
});

afterAll(async () => {
  await rm(dir, { recursive: true, force: true }).catch(() => { });
});

describe("reviewer initialization", () => {
  it("loads outside a repository", async () => {
    const path = join(dir, "plain");
    await mkdir(path);
    const out = await render(path);
    expect(out).toContain("HEAD: none");
    expect(out).not.toContain("Command execution failed");
  });

  it("lists a proposal worktree beside the checkout under review", async () => {
    const path = join(dir, "repo");
    await mkdir(path);
    await sh(path, "git", "init", "-q", "-b", "main");
    await sh(path, "git", "commit", "-q", "--allow-empty", "-m", "root");
    await sh(path, "git", "worktree", "add", "-q", "-b", "review/TASK-1-r0", join(dir, "review-TASK-1-r0"), "HEAD");
    const out = await render(path);
    expect(out).toContain("## main");
    expect(out).toContain("[review/TASK-1-r0]");
    expect(out).not.toContain("Command execution failed");
  });
});
