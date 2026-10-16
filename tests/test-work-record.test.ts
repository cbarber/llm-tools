/**
 * test-work-record.test.ts
 *
 * The coordinator's work record resolves per checkout, is replaced
 * atomically, reports missing or inconsistent state instead of guessing, and
 * maps to exactly one continuation outcome.
 */

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { execFile, spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const workRecord = join(import.meta.dir, "..", "tools", "work-record");

let dir: string;
let env: NodeJS.ProcessEnv;

type Result = { code: number; stdout: string; stderr: string };

async function run(cwd: string, ...args: string[]): Promise<Result> {
  try {
    const { stdout, stderr } = await execFileAsync("bash", [workRecord, ...args], { cwd, env });
    return { code: 0, stdout, stderr };
  } catch (err: any) {
    return { code: err.code, stdout: err.stdout, stderr: err.stderr };
  }
}

async function git(cwd: string, ...args: string[]) {
  await execFileAsync("git", args, { cwd, env });
}

async function repo(name: string): Promise<string> {
  const path = join(dir, name);
  await mkdir(path, { recursive: true });
  await git(path, "init", "-q", "-b", "main");
  await git(path, "commit", "-q", "--allow-empty", "-m", "root");
  return path;
}

async function init(cwd: string, next = "implement TASK-1"): Promise<string> {
  const result = await run(cwd, "init", ".next_action = $a | .current_ticket = \"TASK-1\"", "--arg", "a", next);
  expect(result.code).toBe(0);
  return (await run(cwd, "path")).stdout.trim();
}

beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), "work-record-"));
  env = {
    ...process.env,
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

describe("checkout resolution", () => {
  it("gives each clone and worktree its own record", async () => {
    const main = await repo("resolve-main");
    const clone = join(dir, "resolve-clone", "resolve-main");
    await mkdir(join(dir, "resolve-clone"));
    await git(join(dir, "resolve-clone"), "clone", "-q", main);
    const worktree = join(dir, "resolve-wt");
    await git(main, "worktree", "add", "-q", "-b", "feature", worktree);

    const paths = [await init(main, "main"), await init(clone, "clone"), await init(worktree, "worktree")];
    expect(new Set(paths).size).toBe(3);

    await mkdir(join(main, "sub"));
    expect((await run(join(main, "sub"), "path")).stdout.trim()).toBe(paths[0]);

    expect((await run(worktree, "record", ".next_action = \"worktree updated\"")).code).toBe(0);
    const actions = await Promise.all(
      [main, clone, worktree].map(async (cwd) => JSON.parse((await run(cwd, "read")).stdout).next_action),
    );
    expect(actions).toEqual(["main", "clone", "worktree updated"]);
    expect(JSON.parse((await run(worktree, "read")).stdout)).toMatchObject({ checkout: worktree, branch: "feature" });
  });
});

describe("atomic writes", () => {
  it("never exposes a partial record and loses no concurrent update", async () => {
    const cwd = await repo("atomic");
    const record = await init(cwd);
    const writers = 6;
    const updates = 15;
    // Padding makes each write large enough that an in-place write would be
    // observable mid-flight.
    const padding = "x".repeat(64 * 1024);

    const writes = Array.from({ length: writers }, (_, w) =>
      new Promise<number>((resolve) => {
        const script = `for i in $(seq ${updates}); do bash "$0" record '.agents += [{writer: ${w}, i: $i}] | .pad = $p' --arg p "$1" --argjson i "$i" >/dev/null || exit 1; done`;
        spawn("bash", ["-c", script, workRecord, padding], { cwd, env, stdio: "ignore" }).on("exit", (code) =>
          resolve(code ?? 1),
        );
      }),
    );
    let done = false;
    const all = Promise.all(writes).finally(() => (done = true));

    let reads = 0;
    while (!done) {
      const parsed = JSON.parse(readFileSync(record, "utf8"));
      expect(parsed.checkout).toBe(cwd);
      reads++;
      await Bun.sleep(0);
    }

    expect(await all).toEqual(Array(writers).fill(0));
    expect(reads).toBeGreaterThan(0);
    expect(JSON.parse((await run(cwd, "read")).stdout).agents).toHaveLength(writers * updates);
  });
});

describe("missing or inconsistent record", () => {
  it("reports a missing record", async () => {
    const result = await run(await repo("missing"), "check");
    expect(result).toMatchObject({ code: 3, stdout: "" });
    expect(result.stderr).toContain("no record");
  });

  it("reports unparseable JSON", async () => {
    const cwd = await repo("corrupt");
    await writeFile(await init(cwd), '{"next_action":');
    for (const command of ["read", "check", "record"]) {
      const result = await run(cwd, command, ".");
      expect(result).toMatchObject({ code: 4, stdout: "" });
      expect(result.stderr).toContain("not valid JSON");
    }
  });

  it("stays usable when the checkout leaves the recorded branch", async () => {
    const cwd = await repo("branch");
    await init(cwd);
    await git(cwd, "switch", "-q", "--detach");
    expect((await run(cwd, "check")).stdout.trim()).toBe("continue");
    const result = await run(cwd, "record", ".branch = \"worker\"");
    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout).branch).toBe("worker");
  });

  it("reports a record that belongs to another checkout", async () => {
    const cwd = await repo("foreign");
    const record = await init(cwd);
    await writeFile(record, JSON.stringify({ ...JSON.parse(readFileSync(record, "utf8")), checkout: "/elsewhere" }));
    const result = await run(cwd, "read");
    expect(result.code).toBe(4);
    expect(result.stderr).toContain('checkout is "/elsewhere"');
  });

  it("reports a record with no next action, gate, or completion", async () => {
    const cwd = await repo("stalled");
    const record = await init(cwd);
    await writeFile(record, JSON.stringify({ ...JSON.parse(readFileSync(record, "utf8")), next_action: null }));
    const result = await run(cwd, "check");
    expect(result.code).toBe(4);
    expect(result.stderr).toContain("no next_action, human_gate, or completion recorded");
  });

  it("rejects an update that would make the record inconsistent", async () => {
    const cwd = await repo("rejected");
    const record = await init(cwd);
    const before = readFileSync(record, "utf8");
    for (const filter of [".next_action = null", ".correction_round = -1", ".complete = \"yes\"", "empty"]) {
      expect((await run(cwd, "record", filter)).code).toBe(2);
    }
    expect(readFileSync(record, "utf8")).toBe(before);
  });

  it("refuses to create a record without a next action or gate", async () => {
    const cwd = await repo("bare");
    expect((await run(cwd, "init")).code).toBe(2);
    expect((await run(cwd, "check")).code).toBe(3);
  });
});

describe("revision", () => {
  const revision = async (cwd: string) => JSON.parse((await run(cwd, "read")).stdout).revision;

  it("is bumped by init and every record write, but not by linking a handoff", async () => {
    const cwd = await repo("revision-bump");
    await init(cwd);
    expect(await revision(cwd)).toBe(1);
    expect((await run(cwd, "record", ".")).code).toBe(0);
    expect(await revision(cwd)).toBe(2);
    // The helper owns the counter; a filter cannot set it.
    expect(JSON.parse((await run(cwd, "record", ".revision = 40")).stdout).revision).toBe(3);
    await writeFile(join(cwd, "handoff.md"), "Next: implement TASK-1\n");
    expect((await run(cwd, "handoff", "handoff.md")).code).toBe(0);
    expect(await revision(cwd)).toBe(3);
  });

  it("accepts a record written before the counter existed and starts counting", async () => {
    const cwd = await repo("revision-legacy");
    const record = await init(cwd);
    const { revision: _, ...legacy } = JSON.parse(readFileSync(record, "utf8"));
    await writeFile(record, JSON.stringify(legacy));
    expect((await run(cwd, "check")).stdout.trim()).toBe("continue");
    expect(JSON.parse((await run(cwd, "record", ".")).stdout).revision).toBe(1);
  });

  it("reports a malformed revision", async () => {
    const cwd = await repo("revision-malformed");
    const record = await init(cwd);
    await writeFile(record, JSON.stringify({ ...JSON.parse(readFileSync(record, "utf8")), revision: "one" }));
    const result = await run(cwd, "read");
    expect(result.code).toBe(4);
    expect(result.stderr).toContain("revision must be a non-negative integer");
  });
});

describe("continuation check", () => {
  const cases: [string, string, string][] = [
    ["continue", "remaining work", ".human_gate = null"],
    ["wait-for-human", "pending gate", ".human_gate = \"approve design\""],
    ["complete", "finished work", ".next_action = null | .complete = true"],
    ["wait-for-human", "gate pending after completion", ".next_action = null | .complete = true | .human_gate = \"final review\""],
  ];
  for (const [outcome, label, filter] of cases) {
    it(`returns ${outcome} for ${label}`, async () => {
      const cwd = await repo(`check-${label.replaceAll(" ", "-")}`);
      await init(cwd);
      expect((await run(cwd, "record", filter)).code).toBe(0);
      expect(await run(cwd, "check")).toMatchObject({ code: 0, stdout: `${outcome}\n` });
    });
  }
});

describe("reasoned handoff", () => {
  const state = async (cwd: string) => (await run(cwd, "handoff")).stdout.trim();

  it("is missing until a handoff is linked, and current while the record is unchanged", async () => {
    const cwd = await repo("handoff-current");
    await init(cwd);
    expect(await state(cwd)).toBe("missing");

    await writeFile(join(cwd, "handoff.md"), "Next: implement TASK-1\n");
    const linked = await run(cwd, "handoff", "handoff.md");
    expect(linked.code).toBe(0);
    expect(JSON.parse(linked.stdout).artifacts.handoff.path).toBe(join(cwd, "handoff.md"));
    expect(await run(cwd, "handoff")).toMatchObject({ code: 0, stdout: "current\n" });
  });

  it("goes stale once the record moves on, and current again when relinked", async () => {
    const cwd = await repo("handoff-stale");
    await init(cwd);
    await writeFile(join(cwd, "handoff.md"), "Next: implement TASK-1\n");
    await run(cwd, "handoff", "handoff.md");
    for (const filter of [".next_action = \"review TASK-1 round 0\"", ".human_gate = \"design approval\""]) {
      expect((await run(cwd, "record", filter)).code).toBe(0);
      expect(await state(cwd)).toBe("stale");
      await run(cwd, "handoff", "handoff.md");
      expect(await state(cwd)).toBe("current");
    }
  });

  it("goes stale on a write that sets unchanged values", async () => {
    const cwd = await repo("handoff-same-values");
    await init(cwd);
    await writeFile(join(cwd, "handoff.md"), "Next: implement TASK-1\n");
    await run(cwd, "handoff", "handoff.md");
    // A same-ticket re-dispatch rewrites the fields it already holds.
    expect((await run(cwd, "record", '.current_ticket = "TASK-1" | .next_action = "implement TASK-1"')).code).toBe(0);
    expect(await state(cwd)).toBe("stale");
  });

  it("is current when linked on a record written before the revision counter", async () => {
    const cwd = await repo("handoff-legacy");
    const record = await init(cwd);
    const { revision: _, ...legacy } = JSON.parse(readFileSync(record, "utf8"));
    await writeFile(record, JSON.stringify(legacy));
    await writeFile(join(cwd, "handoff.md"), "Next: implement TASK-1\n");
    expect((await run(cwd, "handoff", "handoff.md")).code).toBe(0);
    expect(await state(cwd)).toBe("current");
    expect((await run(cwd, "record", ".")).code).toBe(0);
    expect(await state(cwd)).toBe("stale");
  });

  it("is missing when the linked file is gone or empty", async () => {
    const cwd = await repo("handoff-gone");
    await init(cwd);
    const file = join(cwd, "handoff.md");
    await writeFile(file, "Next: implement TASK-1\n");
    await run(cwd, "handoff", "handoff.md");
    await writeFile(file, "");
    expect(await state(cwd)).toBe("missing");
    await rm(file);
    expect(await state(cwd)).toBe("missing");
  });

  it("refuses to link an absent or empty file", async () => {
    const cwd = await repo("handoff-refused");
    await init(cwd);
    await writeFile(join(cwd, "empty.md"), "");
    for (const file of ["absent.md", "empty.md"]) {
      expect((await run(cwd, "handoff", file)).code).toBe(2);
    }
    expect(await state(cwd)).toBe("missing");
  });

  for (const filter of ["del(.artifacts)", ".artifacts = null"]) {
    it(`stays current after linking when the record starts with ${filter}`, async () => {
      const cwd = await repo(`handoff-${filter.replace(/\W+/g, "-")}`);
      expect((await run(cwd, "init", `.next_action = "a" | ${filter}`)).code).toBe(0);
      await writeFile(join(cwd, "handoff.md"), "Next: a\n");
      expect((await run(cwd, "handoff", "handoff.md")).code).toBe(0);
      expect(await run(cwd, "handoff")).toMatchObject({ code: 0, stdout: "current\n" });
    });
  }

  it("reads non-object artifacts as missing and refuses to link over them", async () => {
    const cwd = await repo("handoff-array-artifacts");
    expect((await run(cwd, "init", '.next_action = "a" | .artifacts = []')).code).toBe(0);
    expect(await run(cwd, "handoff")).toMatchObject({ code: 0, stdout: "missing\n", stderr: "" });
    await writeFile(join(cwd, "handoff.md"), "Next: a\n");
    expect((await run(cwd, "handoff", "handoff.md")).code).toBe(2);
    expect(JSON.parse((await run(cwd, "read")).stdout).artifacts).toEqual([]);
  });

  it("reports a missing record rather than a handoff state", async () => {
    expect(await run(await repo("handoff-no-record"), "handoff")).toMatchObject({ code: 3, stdout: "" });
  });
});
