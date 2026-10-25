/**
 * test-temper-exec.test.ts
 *
 * Executable skill blocks render identically through the temper CLI and the
 * OpenCode plugin: Claude's ```! fence runs exactly like ```bash {exec},
 * and ordinary ```bash examples never run.
 */

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const root = join(import.meta.dir, "..");
const temperCli = join(root, "tools", "temper");
const temperPlugin = join(root, "agents", "opencode", "plugins", "temper.ts");

const fence = "```";

function skill(opener: string, code: string): string {
  return [
    "---",
    "name: fixture",
    "description: fixture",
    "triggers:",
    "  - event: session.created",
    "---",
    "",
    "# fixture",
    "",
    opener,
    code,
    fence,
    "",
    "Example only:",
    "",
    `${fence}bash`,
    "touch example-ran",
    fence,
    "",
  ].join("\n");
}

const renderers = {
  cli: async (dir: string, name: string) =>
    (await execFileAsync("bash", [temperCli, name], { cwd: dir, env: { ...process.env, HOME: dir } })).stdout,
  plugin: async (dir: string, name: string) =>
    (await execFileAsync("bun", [temperPlugin, join(dir, ".agents", "skills", name, "SKILL.md")], { cwd: dir })).stdout,
};

describe("temper executable blocks", () => {
  let dir: string;

  beforeAll(async () => {
    dir = await mkdtemp(join(tmpdir(), "temper-exec-"));
    const fixtures: Record<string, string> = {
      "claude-ok": skill(`${fence}!`, "echo rendered-output"),
      "exec-ok": skill(`${fence}bash {exec}`, "echo rendered-output"),
      "claude-fail": skill(`${fence}!`, "echo partial\necho boom >&2\n(exit 3)"),
      "exec-fail": skill(`${fence}bash {exec}`, "echo partial\necho boom >&2\n(exit 3)"),
    };
    for (const [name, content] of Object.entries(fixtures)) {
      await mkdir(join(dir, ".agents", "skills", name), { recursive: true });
      await writeFile(join(dir, ".agents", "skills", name, "SKILL.md"), content);
    }
  });

  afterAll(async () => {
    await rm(dir, { recursive: true, force: true }).catch(() => { });
  });

  for (const [renderer, render] of Object.entries(renderers)) {
    describe(renderer, () => {
      it("substitutes ! block output and leaves examples unexecuted", async () => {
        const out = await render(dir, "claude-ok");
        expect(out).toContain("rendered-output");
        expect(out).not.toContain("echo rendered-output");
        expect(out).toContain("touch example-ran");
        expect(existsSync(join(dir, "example-ran"))).toBe(false);
      });

      it("renders ! blocks exactly as bash {exec} blocks", async () => {
        expect(await render(dir, "claude-ok")).toBe(await render(dir, "exec-ok"));
      });

      it("reports ! block failures exactly as bash {exec} failures", async () => {
        const out = await render(dir, "claude-fail");
        expect(out).toContain("partial");
        expect(out).toContain("Command execution failed (exit code: 3)");
        expect(out).toContain("boom");
        expect(out).toBe(await render(dir, "exec-fail"));
      });
    });
  }
});
