import { afterAll, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
import { TemperPlugin } from "./temper";

const root = await mkdtemp(join(tmpdir(), "temper-workflow-"));
const directory = join(root, "repo");
const stateHome = join(root, "state");
await Bun.$`mkdir -p ${directory}`;
await Bun.$.cwd(directory)`git init -q`;
await Bun.$.cwd(directory)`git config user.name Test`;
await Bun.$.cwd(directory)`git config user.email test@example.com`;
await writeFile(join(directory, "README.md"), "initial\n");
await Bun.$.cwd(directory)`git add README.md`;
await Bun.$.cwd(directory)`git commit -qm initial`;

const skillsRoot = resolve(import.meta.dir, "../../skills");
const skillNames = [
  "mojo-init",
  "mojo-edit-nudge",
  "mojo-commit",
  "mojo-create-pull-request",
  "mojo-update-pull-request",
];
const legacySkill = join(root, "mojo-complete", "SKILL.md");
await mkdir(join(root, "mojo-complete"));
await writeFile(legacySkill, '---\nname: mojo-complete\ntriggers:\n  - event: session.idle\n    when: "true"\n---\n# mojo-complete\n');
const server = Bun.serve({
  port: 0,
  fetch(request) {
    if (new URL(request.url).pathname === "/skill") {
      return Response.json([...skillNames.map((name) => ({
        name,
        description: name,
        location: join(skillsRoot, name, "SKILL.md"),
      })), { name: "mojo-complete", description: "legacy completion", location: legacySkill }]);
    }
    return Response.json([]);
  },
});

afterAll(async () => {
  server.stop(true);
  await rm(root, { recursive: true, force: true });
});

describe("Temper workflow adapter", () => {
  test("records legacy skill injection in the session trace", async () => {
    const previousStateHome = process.env.XDG_STATE_HOME;
    const legacyHome = join(root, "legacy-state");
    process.env.XDG_STATE_HOME = legacyHome;
    const sessionID = "legacy-session";
    const prompts: string[] = [];
    const client = {
      app: { log: async () => ({}) },
      session: { prompt: async ({ body }: { body: { parts: Array<{ text: string }> } }) => {
        prompts.push(body.parts[0].text);
        return {};
      } },
    };
    try {
      const hooks = await TemperPlugin({ client, $: Bun.$, directory, serverUrl: server.url } as never);
      await hooks.event!({ event: { type: "session.created", properties: { info: { id: sessionID } } } } as never);
      await hooks.event!({ event: { type: "session.idle", properties: { sessionID } } } as never);
      expect(prompts[0]).toContain("# mojo-complete");
      const hash = createHash("sha256").update(sessionID).digest("hex");
      const trace = (await readFile(join(legacyHome, "opencode", "temper", `${hash}.jsonl`), "utf8"))
        .trim().split("\n").map((line) => JSON.parse(line));
      expect(trace).toContainEqual(expect.objectContaining({ event: "skills.injected", source: "legacy", skills: ["mojo-complete"], reply: false }));
      await hooks.dispose?.();
    } finally {
      if (previousStateHome === undefined) delete process.env.XDG_STATE_HOME;
      else process.env.XDG_STATE_HOME = previousStateHome;
    }
  });

  test("rejects a mismatched restore and permits fresh activation", async () => {
    const previousStateHome = process.env.XDG_STATE_HOME;
    const restoreHome = join(root, "restore-state");
    process.env.XDG_STATE_HOME = restoreHome;
    const sessionID = "mismatched-workflow";
    const hash = createHash("sha256").update(sessionID).digest("hex");
    const file = join(restoreHome, "opencode", "temper", `${hash}.json`);
    const prompts: string[] = [];
    const client = {
      app: { log: async () => ({}) },
      session: { prompt: async ({ body }: { body: { parts: Array<{ text: string }> } }) => {
        prompts.push(body.parts[0].text);
        return {};
      } },
    };
    try {
      const original = await TemperPlugin({ client, $: Bun.$, directory, serverUrl: server.url } as never);
      await original["command.execute.before"]!({ command: "mojo-init", sessionID, arguments: "" }, { parts: [] } as never);
      const envelope = JSON.parse(await readFile(file, "utf8"));
      envelope.sourceHash = "outdated";
      await writeFile(file, JSON.stringify(envelope));
      await original.dispose?.();

      const restored = await TemperPlugin({ client, $: Bun.$, directory, serverUrl: server.url } as never);
      await restored["chat.message"]!({ sessionID } as never, { parts: [{ type: "text", text: "hello" }] } as never);
      expect(prompts).toHaveLength(1);
      expect(await stat(file).catch(() => undefined)).toBeUndefined();
      const trace = (await readFile(file.replace(/\.json$/, ".jsonl"), "utf8")).trim().split("\n").map((line) => JSON.parse(line));
      expect(trace).toContainEqual(expect.objectContaining({ event: "workflow.restore-failed", error: "Error: Workflow definition changed" }));
      await restored["command.execute.before"]!({ command: "mojo-init", sessionID, arguments: "" }, { parts: [] } as never);
      expect(prompts).toHaveLength(2);
      await restored.dispose?.();
    } finally {
      if (previousStateHome === undefined) delete process.env.XDG_STATE_HOME;
      else process.env.XDG_STATE_HOME = previousStateHome;
    }
  });

  test("activates, replaces, persists, and stops the Mojo workflow", async () => {
    const previousStateHome = process.env.XDG_STATE_HOME;
    process.env.XDG_STATE_HOME = stateHome;
    const prompts: Array<{ noReply?: boolean; parts: Array<{ text: string; synthetic?: boolean }> }> = [];
    const client = {
      app: { log: async () => ({}) },
      session: {
        prompt: async ({ body }: { body: { noReply?: boolean; parts: Array<{ text: string; synthetic?: boolean }> } }) => {
          prompts.push(body);
          return {};
        },
      },
    };
    const hooks = await TemperPlugin({ client, $: Bun.$, directory, serverUrl: server.url } as never);

    const slashOutput = { parts: [{ type: "text", text: "native expansion" }] };
    await hooks["command.execute.before"]!({ command: "mojo-init", sessionID: "workflow-session", arguments: "" }, slashOutput as never);
    expect(slashOutput.parts).toEqual([]);
    expect(prompts).toHaveLength(1);
    expect(prompts[0].parts[0].text).toContain("# mojo-init");
    expect(prompts[0].parts[0].text).toContain("# mojo-edit-nudge");

    const files = await Array.fromAsync(new Bun.Glob("*.json").scan({ cwd: join(stateHome, "opencode", "temper"), absolute: true }));
    expect(files).toHaveLength(1);
    expect((await stat(files[0])).mode & 0o777).toBe(0o600);
    expect(JSON.parse(await readFile(files[0], "utf8")).workflowId).toBe("mojo");

    await hooks["tool.execute.before"]!({ tool: "skill", sessionID: "workflow-session", callID: "replace" }, { args: { name: "mojo-init" } });
    expect(prompts).toHaveLength(2);

    await hooks.event!({ event: { type: "session.created", properties: { info: { id: "workflow-session" } } } } as never);
    const part = {
      id: "provider-edit",
      sessionID: "workflow-session",
      messageID: "provider-message",
      callID: "provider-call",
      type: "tool",
      tool: "edit",
      metadata: { providerExecuted: true },
      state: { status: "running", input: { filePath: "change.ts" } },
    };
    await hooks.event!({ event: { type: "message.part.updated", properties: { part } } } as never);
    await writeFile(join(directory, "change.ts"), "edited\n");
    const completed = { ...part, state: { ...part.state, status: "completed", output: "edited" } };
    await hooks.event!({ event: { type: "message.part.updated", properties: { part: completed } } } as never);
    await hooks.event!({ event: { type: "message.part.updated", properties: { part: completed } } } as never);
    const traceFile = join(stateHome, "opencode", "temper", `${createHash("sha256").update("workflow-session").digest("hex")}.jsonl`);
    const finished = (await readFile(traceFile, "utf8")).trim().split("\n").map((line) => JSON.parse(line))
      .filter((record) => record.event === "tool.finished" && record.callID === "provider-call");
    expect(finished).toHaveLength(1);
    expect(finished[0].before.dirty).toBe(false);
    expect(finished[0].after.dirty).toBe(true);

    const result = await hooks.tool!.temper_workflow_stop.execute({}, {
      sessionID: "workflow-session",
      directory,
    } as never);
    expect(result).toBe("Stopped the active Temper workflow.");
    expect(await stat(files[0]).catch(() => undefined)).toBeUndefined();

    await hooks.event!({ event: { type: "message.part.updated", properties: {
      part: { ...completed, id: "replayed-skill", callID: "replayed-skill", tool: "skill", state: { ...completed.state, input: { name: "mojo-init" } } },
    } } } as never);
    expect(prompts).toHaveLength(2);

    await hooks.dispose?.();
    if (previousStateHome === undefined) delete process.env.XDG_STATE_HOME;
    else process.env.XDG_STATE_HOME = previousStateHome;
  });

  test("uses the project workflow, traces rendered skills, and suppresses legacy completion", async () => {
    const previousStateHome = process.env.XDG_STATE_HOME;
    const localStateHome = join(root, "project-state");
    process.env.XDG_STATE_HOME = localStateHome;
    const localSource = join(directory, "agents", "skills", "mojo-init", "workflow.ts");
    const sessionID = "project-workflow";
    const hash = createHash("sha256").update(sessionID).digest("hex");
    const prompts: string[] = [];
    const client = {
      app: { log: async () => ({}) },
      session: { prompt: async ({ body }: { body: { parts: Array<{ text: string }> } }) => {
        prompts.push(body.parts[0].text);
        return {};
      } },
    };
    await mkdir(join(directory, "agents", "skills", "mojo-init"), { recursive: true });
    await writeFile(localSource, await readFile(join(skillsRoot, "mojo-init", "workflow.ts")));
    try {
      const hooks = await TemperPlugin({ client, $: Bun.$, directory, serverUrl: server.url } as never);
      await hooks["tool.execute.before"]!({ tool: "skill", sessionID, callID: "activate" }, { args: { name: "mojo-init" } });
      const statePath = join(localStateHome, "opencode", "temper", `${hash}.json`);
      expect(JSON.parse(await readFile(statePath, "utf8")).source).toBe(localSource);
      const tracePath = join(localStateHome, "opencode", "temper", `${hash}.jsonl`);
      const trace = (await readFile(tracePath, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
      expect(trace).toContainEqual(expect.objectContaining({ event: "skills.injected", source: "workflow", skills: ["mojo-edit-nudge"], reply: false }));
      await hooks.event!({ event: { type: "session.created", properties: { info: { id: sessionID } } } } as never);
      await Promise.all(Array.from({ length: 12 }, () => hooks["chat.message"]!(
        { sessionID } as never, { parts: [{ type: "text", text: "hello" }] } as never,
      )));
      expect(JSON.parse(await readFile(statePath, "utf8")).workflowId).toBe("mojo");
      await hooks.event!({ event: { type: "session.idle", properties: { sessionID } } } as never);
      expect(prompts).toHaveLength(1);
      await hooks.dispose?.();
    } finally {
      await rm(join(directory, "agents"), { recursive: true, force: true });
      if (previousStateHome === undefined) delete process.env.XDG_STATE_HOME;
      else process.env.XDG_STATE_HOME = previousStateHome;
    }
  });
});
