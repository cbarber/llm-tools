import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
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
const server = Bun.serve({
  port: 0,
  fetch(request) {
    if (new URL(request.url).pathname === "/skill") {
      return Response.json(skillNames.map((name) => ({
        name,
        description: name,
        location: join(skillsRoot, name, "SKILL.md"),
      })));
    }
    return Response.json([]);
  },
});

afterAll(async () => {
  server.stop(true);
  await rm(root, { recursive: true, force: true });
});

describe("Temper workflow adapter", () => {
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
});
