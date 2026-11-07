/**
 * test-mojo-handoff.test.ts
 *
 * The mojo-handoff skill's initialization shows the work record and where
 * the handoff goes without failing the skill load, and its documented link
 * step binds the written handoff to the current record state.
 */

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
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
  const out = await sh(cwd, "bash", join(root, "tools", "temper"), "mojo-handoff");
  return out.slice(0, out.indexOf("# mojo-handoff"));
}

async function repo(name: string): Promise<string> {
  const path = join(dir, name);
  await mkdir(path);
  await sh(path, "git", "init", "-q", "-b", "main");
  await sh(path, "git", "commit", "-q", "--allow-empty", "-m", "root");
  return path;
}

// Runs the first bash block the skill documents after a heading.
async function documented(cwd: string, heading: string): Promise<string> {
  const skill = await readFile(join(root, "agents", "skills", "mojo-handoff", "SKILL.md"), "utf8");
  const at = skill.indexOf(`## ${heading}\n`);
  const block = at < 0 ? null : skill.slice(at).match(/```bash\n([\s\S]*?)```/);
  if (!block) throw new Error(`no commands after "${heading}" in SKILL.md`);
  return sh(cwd, "bash", "-euo", "pipefail", "-c", block[1]);
}

beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), "mojo-handoff-"));
  const home = join(dir, "home");
  const bin = join(dir, "bin");
  await mkdir(join(home, ".agents", "skills"), { recursive: true });
  await cp(join(root, "agents", "skills", "mojo-handoff"), join(home, ".agents", "skills", "mojo-handoff"), {
    recursive: true,
  });
  await mkdir(bin);
  await symlink(join(root, "tools", "work-record"), join(bin, "work-record"));
  env = {
    ...process.env,
    HOME: home,
    PATH: `${bin}:${process.env.PATH}`,
    WORK_RECORD_HOME: join(dir, "store"),
    GIT_AUTHOR_NAME: "t",
    GIT_AUTHOR_EMAIL: "t@example.com",
    GIT_COMMITTER_NAME: "t",
    GIT_COMMITTER_EMAIL: "t@example.com",
  };
});

afterAll(async () => {
  await rm(dir, { recursive: true, force: true }).catch(() => { });
});

describe("initialization", () => {
  it("reports a missing record", async () => {
    const out = await render(await repo("no-record"));
    expect(out).toContain("work-record: no record for");
    expect(out).not.toContain("Command execution failed");
  });

  it("reports an inconsistent record", async () => {
    const path = await repo("inconsistent");
    const file = (await sh(path, "work-record", "path")).trim();
    await mkdir(join(file, ".."), { recursive: true });
    await writeFile(file, "{}\n");
    const out = await render(path);
    expect(out).toContain("inconsistent record");
    expect(out).not.toContain("Command execution failed");
  });

  it("shows the record, its handoff state, and where the handoff goes", async () => {
    const path = await repo("present");
    await sh(path, "work-record", "init", '.next_action = "review TASK-1 round 0"');
    const out = await render(path);
    expect(out).toContain('"next_action": "review TASK-1 round 0"');
    expect(out).toContain("Continuation: continue");
    expect(out).toContain("Handoff: missing");
    const record = (await sh(path, "work-record", "path")).trim();
    expect(out).toContain("Previous handoff: none");
    expect(out).toContain(`Handoff file: ${join(record, "..", "handoffs", "001.md")}`);
  });
});

describe("linking", () => {
  it("binds the written handoff to the current record", async () => {
    const path = await repo("link");
    await sh(path, "work-record", "init", '.next_action = "review TASK-1 round 0"');
    const handoffs = join((await sh(path, "work-record", "path")).trim(), "..", "handoffs");
    await mkdir(handoffs);
    await writeFile(join(handoffs, "001.md"), "# Handoff: TASK-1\n");
    expect(await documented(path, "Link it")).toBe("current\n");
    expect(await render(path)).toContain("Handoff: current");
  });

  it("appends each handoff after the earlier ones and links the newest", async () => {
    const path = await repo("append");
    await sh(path, "work-record", "init", '.next_action = "review TASK-1 round 0"');
    const handoffs = join((await sh(path, "work-record", "path")).trim(), "..", "handoffs");
    await mkdir(handoffs);
    await writeFile(join(handoffs, "001.md"), "# Handoff: TASK-1 first\n");
    await documented(path, "Link it");
    await sh(path, "work-record", "record", '.next_action = "correct TASK-1 round 1"');
    await expect(documented(path, "Link it")).rejects.toThrow("no new handoff");

    const out = await render(path);
    expect(out).toContain(`Previous handoff: ${join(handoffs, "001.md")}`);
    expect(out).toContain(`Handoff file: ${join(handoffs, "002.md")}`);
    await writeFile(join(handoffs, "002.md"), "# Handoff: TASK-1 second\n");
    expect(await documented(path, "Link it")).toBe("current\n");
    const linked = JSON.parse(await sh(path, "work-record", "read")).artifacts.handoff.path;
    expect(linked).toBe(join(handoffs, "002.md"));
    expect(await readFile(join(handoffs, "001.md"), "utf8")).toBe("# Handoff: TASK-1 first\n");
    const skill = await readFile(join(root, "agents", "skills", "mojo-handoff", "SKILL.md"), "utf8");
    expect(skill).toMatch(/## Rulings\n<The Rulings list of the `Previous handoff` above, copied in full/);
    expect(skill).toMatch(/a ruling the human withdraws stays, marked withdrawn/);
  });

  it("fails rather than linking a handoff that was not written", async () => {
    const path = await repo("unwritten");
    await sh(path, "work-record", "init", '.next_action = "review TASK-1 round 0"');
    await expect(documented(path, "Link it")).rejects.toThrow("no new handoff");
  });
});
