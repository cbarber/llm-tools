import type { MockServer } from "llm-mock-server";
import { execFile, spawn } from "node:child_process";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { createServer } from "node:net";

const execFileAsync = promisify(execFile);

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

export async function findFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = createServer();
    srv.listen(0, "127.0.0.1", () => {
      const addr = srv.address() as { port: number };
      srv.close(() => resolve(addr.port));
    });
    srv.on("error", reject);
  });
}

export async function waitFor(
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

export async function createFixtureRepo(): Promise<string> {
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
  await mkdir(join(dir, ".opencode"));
  return dir;
}

export async function writeOpencodeConfig(dir: string, mockBaseUrl: string): Promise<void> {
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

export async function startOpencode(dir: string, port: number): Promise<() => void> {
  const nixSmithDir = join(import.meta.dir, "..");
  const stderr: Buffer[] = [];

  const inSandbox = process.env.IN_AGENT_SANDBOX === "1";
  const [cmd, args]: [string, string[]] = inSandbox
    ? ["opencode", ["serve", "--port", String(port)]]
    : ["nix", ["develop", `${nixSmithDir}#opencode`, "--command", "bash", "-c", `agent-sandbox opencode serve --port ${port}`]];

  const proc = spawn(
    cmd,
    args,
    {
      cwd: dir,
      env: { ...process.env, OPENCODE_PORT: String(port), AUTO_LAUNCH: "false", ANTHROPIC_API_KEY: "" },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  const debug = process.env.HARNESS_DEBUG === "1";
  proc.stderr?.on("data", (d: Buffer) => {
    stderr.push(d);
    if (debug) process.stderr.write(d);
  });

  let exitCode: number | null = null;
  proc.on("exit", (code) => { exitCode = code ?? 1; });

  if (debug) process.stderr.write(`[harness] startOpencode: waiting for port ${port}\n`);
  await waitFor(async () => {
    if (exitCode !== null) throw new Error(`opencode exited with code ${exitCode}`);
    try {
      const ok = (await fetch(`http://127.0.0.1:${port}/session`, { signal: AbortSignal.timeout(4_000) })).ok;
      if (ok && debug) process.stderr.write(`[harness] startOpencode: port ${port} ready\n`);
      return ok;
    }
    catch (e) {
      if (debug) process.stderr.write(`[harness] startOpencode: fetch attempt failed: ${e}\n`);
      return false;
    }
  }, 30_000, "opencode serve to start").catch((err) => {
    process.stderr.write("[opencode stderr]\n" + Buffer.concat(stderr).toString() + "\n");
    proc.kill("SIGTERM");
    throw err;
  });

  return () => {
    proc.kill("SIGTERM");
    if (debug && stderr.length) process.stderr.write(Buffer.concat(stderr).toString());
  };
}

export async function createSession(port: number, dir: string): Promise<string> {
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
export async function sendPromptAndWait(
  port: number,
  sessionID: string,
  text: string,
  mock: MockServer,
): Promise<void> {
  const debug = process.env.HARNESS_DEBUG === "1";
  if (debug) process.stderr.write(`[harness] sendPromptAndWait: posting prompt\n`);
  await fetch(`http://127.0.0.1:${port}/session/${sessionID}/message`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      noReply: false,
      parts: [{ type: "text", text, synthetic: false }],
    }),
    signal: AbortSignal.timeout(10_000),
  }).then((r) => r.text());
  if (debug) process.stderr.write(`[harness] sendPromptAndWait: prompt posted, waiting for history to stabilize\n`);

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

export async function restartOpencode(
  stop: () => void,
  dir: string,
  port: number,
  waitMs = 1_500,
): Promise<() => void> {
  stop();
  await new Promise((r) => setTimeout(r, waitMs));
  return startOpencode(dir, port);
}

export async function verifySession(port: number, sessionID: string): Promise<void> {
  const res = await fetch(`http://127.0.0.1:${port}/session/${sessionID}`);
  if (!res.ok) {
    throw new Error(`verifySession: expected 200, got ${res.status} for session ${sessionID}`);
  }
  const body = (await res.json()) as { id?: string };
  if (body.id !== sessionID) {
    throw new Error(`verifySession: returned id "${body.id}" does not match expected "${sessionID}"`);
  }
}
