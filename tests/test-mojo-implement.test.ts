/**
 * test-mojo-implement.test.ts
 *
 * The mojo-implement entry skill's initialization selects the next
 * unblocked ticket from the approved set in the work record, reports a
 * missing backlog or a missing/inconsistent record without failing the
 * skill load, and reports completion once every approved ticket is Done.
 */

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
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
  const out = await sh(cwd, "bash", join(root, "tools", "temper"), "mojo-implement");
  return out.slice(0, out.indexOf("# mojo-implement"));
}

async function repo(name: string, backlog = true): Promise<string> {
  const path = join(dir, name);
  await mkdir(path);
  await sh(path, "git", "init", "-q", "-b", "main");
  await sh(path, "git", "commit", "-q", "--allow-empty", "-m", "root");
  if (backlog) {
    await sh(path, "backlog", "init", name, "--defaults", "--agent-instructions", "none");
    await sh(path, "backlog", "config", "set", "remoteOperations", "false");
    await sh(path, "backlog", "config", "set", "checkActiveBranches", "false");
  }
  return path;
}

async function record(cwd: string, filter: string, ...args: string[]) {
  await sh(cwd, "work-record", "record", filter, ...args);
}

beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), "mojo-implement-"));
  const home = join(dir, "home");
  const bin = join(dir, "bin");
  await mkdir(join(home, ".agents", "skills"), { recursive: true });
  await cp(join(root, "agents", "skills", "mojo-implement"), join(home, ".agents", "skills", "mojo-implement"), {
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

describe("absent state", () => {
  it("reports a checkout without a backlog", async () => {
    const out = await render(await repo("no-backlog", false));
    expect(out).toContain("No backlog in this checkout.");
    expect(out).not.toContain("Command execution failed");
  });

  it("reports a missing record", async () => {
    const out = await render(await repo("no-record"));
    expect(out).toContain("work-record: no record for");
    expect(out).toContain("No approved ticket set");
    expect(out).not.toContain("Command execution failed");
  });

  it("reports an inconsistent record", async () => {
    const path = await repo("inconsistent");
    const file = (await sh(path, "work-record", "path")).trim();
    await mkdir(join(file, ".."), { recursive: true });
    await writeFile(file, "{}\n");
    const out = await render(path);
    expect(out).toContain("inconsistent record");
    expect(out).toContain("No approved ticket set");
    expect(out).not.toContain("Command execution failed");
  });
});

describe("approved ticket progression", () => {
  let path: string;

  beforeAll(async () => {
    path = await repo("progression");
    await sh(path, "backlog", "task", "create", "Unrelated ready work");
    await sh(path, "backlog", "task", "create", "Greeting");
    await sh(path, "backlog", "task", "create", "Farewell", "--dep", "task-2");
    await sh(path, "work-record", "init", '.next_action = "select next ticket" | .artifacts.tickets = $t', "--argjson", "t", '["task-2","TASK-3"]');
  });

  it("selects the first unblocked approved ticket, ignoring other ready work", async () => {
    const out = await render(path);
    expect(out).toContain("TASK-2  To Do, unblocked  Greeting");
    expect(out).toContain("TASK-3  To Do, blocked  Farewell");
    expect(out).not.toContain("TASK-1");
    expect(out).toContain("Next ticket: TASK-2 - Greeting");
  });

  it("keeps the dispatched ticket current until it is reconciled", async () => {
    await record(path, '.current_ticket = "TASK-2" | .next_action = "reconcile TASK-2 implementer report"');
    expect(await render(path)).toContain("Next ticket: TASK-2 (current ticket");

    await sh(path, "backlog", "task", "edit", "2", "--status", "Done");
    expect(await render(path)).toContain("Current ticket TASK-2 is closed but not yet reconciled");
  });

  it("advances to the ticket its completion unblocked", async () => {
    await record(path, '.current_ticket = null | .next_action = "select next ticket"');
    expect(await render(path)).toContain("Next ticket: TASK-3 - Farewell");
  });

  it("reports completion when every approved ticket is Done", async () => {
    await sh(path, "backlog", "task", "edit", "3", "--status", "Done");
    expect(await render(path)).toContain("Next ticket: none; all 2 approved tickets are Done.");
  });

  it("names approved tickets blocked outside the approved set", async () => {
    await sh(path, "backlog", "task", "create", "Waits on unrelated", "--dep", "task-1");
    await record(path, ".artifacts.tickets += [\"TASK-4\"]");
    expect(await render(path)).toContain("Next ticket: none; remaining tickets are blocked or missing: TASK-4");
  });
});
