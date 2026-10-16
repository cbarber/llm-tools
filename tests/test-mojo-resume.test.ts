/**
 * test-mojo-resume.test.ts
 *
 * The mojo-resume entry skill's initialization reloads the work record and
 * a current handoff with the commits made since it, consumes the handoff on
 * resume so the Stop hook continues the work, reports a missing or
 * stale handoff instead of its content, leaves a pending human gate
 * untouched, and its documented pause records a gate the Stop hook honors.
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
  const out = await sh(cwd, "bash", join(root, "tools", "temper"), "mojo-resume");
  return out.slice(0, out.indexOf("# mojo-resume"));
}

async function repo(name: string): Promise<string> {
  const path = join(dir, name);
  await mkdir(path);
  await sh(path, "git", "init", "-q", "-b", "main");
  await sh(path, "git", "commit", "-q", "--allow-empty", "-m", "root");
  return path;
}

// Runs the first bash block the skill documents after a bold label.
async function documented(cwd: string, label: string) {
  const skill = await readFile(join(root, "agents", "skills", "mojo-resume", "SKILL.md"), "utf8");
  const at = skill.indexOf(`**${label}**`);
  const block = at < 0 ? null : skill.slice(at).match(/```bash\n([\s\S]*?)```/);
  if (!block) throw new Error(`no commands after "${label}" in SKILL.md`);
  await sh(cwd, "bash", "-euo", "pipefail", "-c", block[1]);
}

// Writes and links a handoff the way mojo-handoff does.
async function handoff(cwd: string, body: string) {
  const file = join((await sh(cwd, "work-record", "path")).trim(), "..", "handoff.md");
  await writeFile(file, body);
  await sh(cwd, "work-record", "handoff", file);
}

const check = async (cwd: string) => (await sh(cwd, "work-record", "check")).trim();

beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), "mojo-resume-"));
  const home = join(dir, "home");
  const bin = join(dir, "bin");
  await mkdir(join(home, ".agents", "skills"), { recursive: true });
  await cp(join(root, "agents", "skills", "mojo-resume"), join(home, ".agents", "skills", "mojo-resume"), {
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
});

describe("current handoff", () => {
  it("restores the interrupted action with the commits made since the handoff", async () => {
    const path = await repo("current");
    const head = (await sh(path, "git", "rev-parse", "HEAD")).trim();
    await sh(path, "work-record", "init", '.current_ticket = "TASK-1" | .next_action = "reconcile TASK-1 implementer report"');
    await handoff(path, `# Handoff: TASK-1\n\nHEAD: ${head}\n\n## Interrupted action\nImplementer for TASK-1 running as agent a1.\n`);
    await sh(path, "git", "commit", "-q", "--allow-empty", "-m", "feat: greeting");

    const out = await render(path);
    expect(out).toContain("Continuation: continue");
    expect(out).toMatch(/Handoff: current \(.*handoff\.md\)/);
    expect(out).toContain("Implementer for TASK-1 running as agent a1.");
    expect(out).toContain(`Commits since handoff (${head}):`);
    expect(out).toContain("feat: greeting");
    expect(out).not.toContain("Command execution failed");
  });

  it("consumes the handoff so premature stops continue and a second renewal pauses", async () => {
    const path = await repo("consumed");
    await sh(path, "work-record", "init", '.current_ticket = "TASK-1" | .next_action = "implement TASK-1"');
    await handoff(path, "# Handoff: TASK-1\n\n## Interrupted action\nImplement TASK-1.\n");
    const stop = () =>
      sh(path, "bash", "-c", '"$0" <<<"$1"', join(root, "tools", "claude-code-scripts", "stop-continue"),
        JSON.stringify({ cwd: path, stop_hook_active: false }));
    // Waiting for renewal: the Stop hook lets the handed-off context stop.
    expect(await stop()).toBe("");

    expect(await render(path)).toContain("Handoff: current");
    await documented(path, "Consume the handoff.");
    expect((await sh(path, "work-record", "handoff")).trim()).toBe("stale");
    const record = JSON.parse(await sh(path, "work-record", "read"));
    expect(record).toMatchObject({ next_action: "implement TASK-1", human_gate: null });
    expect(JSON.parse(await stop()).decision).toBe("block");

    // Renewed again without a new handoff: the consumed one is withheld.
    const out = await render(path);
    expect(out).toContain("Handoff: stale");
    expect(out).not.toContain("Implement TASK-1.");
  });

  it("says when the handoff's HEAD cannot anchor the commits since it", async () => {
    const path = await repo("unanchored");
    await sh(path, "work-record", "init", '.next_action = "implement TASK-1"');
    await handoff(path, "# Handoff: TASK-1\n");
    expect(await render(path)).toContain("Commits since handoff: unknown");

    await handoff(path, "# Handoff: TASK-1\n\nHEAD: 0000000000000000000000000000000000000000\n");
    const out = await render(path);
    expect(out).toContain("does not resolve");
    expect(out).not.toContain("Command execution failed");
  });
});

describe("missing or stale handoff", () => {
  for (const state of ["missing", "stale"]) {
    it(`withholds a ${state} handoff and pauses for the human`, async () => {
      const path = await repo(`pause-${state}`);
      await sh(path, "work-record", "init", '.next_action = "implement TASK-1"');
      if (state === "stale") {
        await handoff(path, "# Handoff: TASK-1\n\nSuperseded reasoning.\n");
        await sh(path, "work-record", "record", '.next_action = "review TASK-1 round 0"');
      }

      const out = await render(path);
      expect(out).toContain(`Handoff: ${state}`);
      expect(out).not.toContain("Superseded reasoning.");

      await documented(path, "Handoff `missing` or `stale`:");
      expect(await check(path)).toBe("wait-for-human");
      const record = JSON.parse(await sh(path, "work-record", "read"));
      expect(record.human_gate).toContain(`without a current handoff (${state})`);
      expect(record.next_action).toBe(state === "stale" ? "review TASK-1 round 0" : "implement TASK-1");
    });
  }
});

describe("pending human gate", () => {
  it("stays pending through resume, whatever the handoff state", async () => {
    const path = await repo("gate");
    const gate = "TASK-1: unresolved blocking findings after 3 correction rounds";
    await sh(path, "work-record", "init", '.next_action = "correct TASK-1 round 3" | .human_gate = $g', "--arg", "g", gate);
    for (const state of ["missing", "current"]) {
      if (state === "current") await handoff(path, "# Handoff: TASK-1\n\n## Human gate and approvals\nPending.\n");
      const before = await sh(path, "work-record", "read");
      const out = await render(path);
      expect(out).toContain(`"human_gate": "${gate}"`);
      expect(out).toContain("Continuation: wait-for-human");
      expect(out).toContain(`Handoff: ${state}`);
      expect(await sh(path, "work-record", "read")).toBe(before);
    }
  });
});
