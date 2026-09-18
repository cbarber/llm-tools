import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { TemperPlugin } from "./temper";

const directory = await mkdtemp(join(tmpdir(), "temper-provider-events-"));
const skillFile = join(directory, "SKILL.md");
await writeFile(skillFile, `---
name: native-edit
description: Test native edit injection
triggers:
  - event: tool.execute.after
    tool: edit
  - event: session.idle
---

# native-edit

Native edit context.
`);

let history: unknown[] = [];
let historyDelay = 0;
let historyFailures = 0;

const server = Bun.serve({
  port: 0,
  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (path === "/skill") {
      return Response.json([{ name: "native-edit", description: "Test native edit injection", location: skillFile }]);
    }
    if (path.endsWith("/message")) {
      if (historyDelay) await Bun.sleep(historyDelay);
      if (historyFailures > 0) {
        historyFailures--;
        return new Response("failed", { status: 500 });
      }
      return Response.json(history);
    }
    return Response.json([]);
  },
});

afterAll(async () => {
  server.stop(true);
  await rm(directory, { recursive: true, force: true });
});

describe("Temper provider tool events", () => {
  test("injects queued native edit context once after session idle", async () => {
    const prompts: Array<{ noReply?: boolean; parts: Array<{ type?: string; text: string; synthetic?: boolean }> }> = [];
    const client = {
      app: { log: async () => ({}) },
      session: {
        prompt: async ({ body }: { body: { noReply?: boolean; parts: Array<{ type?: string; text: string; synthetic?: boolean }> } }) => {
          prompts.push(body);
          return {};
        },
      },
    };
    const hooks = await TemperPlugin({ client, $: Bun.$, directory, serverUrl: server.url } as never);
    const event = hooks.event!;
    const part = {
      id: "part-edit",
      sessionID: "session-native",
      messageID: "message-native",
      type: "tool",
      callID: "call-edit",
      tool: "edit",
      metadata: { providerExecuted: true },
      state: {
        status: "completed",
        input: { filePath: "changed.ts" },
        title: "changed.ts",
        output: "Edit applied.",
        metadata: { diff: "diff" },
        time: { start: 1, end: 2 },
      },
    };

    await event({ event: { type: "session.created", properties: { info: { id: "session-native" } } } } as never);
    await event({ event: { type: "message.part.updated", properties: { part } } } as never);
    await event({ event: { type: "message.part.updated", properties: { part } } } as never);
    expect(prompts).toEqual([]);

    await event({ event: { type: "session.idle", properties: { sessionID: "session-native" } } } as never);
    expect(prompts).toHaveLength(3);
    expect(prompts[0].noReply).toBe(true);
    expect(prompts[0].parts[0].text).toContain("# native-edit");
    expect(prompts[1].noReply).toBe(true);
    expect(prompts[2]).toEqual({
      noReply: false,
      parts: [{ type: "text", text: "Continue with the injected workflow context.", synthetic: true }],
    });

    prompts.length = 0;
    const now = Date.now();
    const resumedPart = {
      ...part,
      id: "part-resumed",
      sessionID: "session-resumed",
      callID: "call-resumed",
      state: { ...part.state, time: { start: now, end: now + 10_000 } },
    };
    history = [{ info: {}, parts: [resumedPart] }];
    historyDelay = 20;
    await hooks["chat.message"]!({ sessionID: "session-resumed" } as never, {} as never);
    const hydration = event({ event: { type: "session.status", properties: { sessionID: "session-resumed" } } } as never);
    await event({ event: { type: "message.part.updated", properties: { part: resumedPart } } } as never);
    await hydration;
    historyDelay = 0;
    await event({ event: { type: "session.idle", properties: { sessionID: "session-resumed" } } } as never);
    expect(prompts.filter((prompt) => prompt.parts[0].text === "Continue with the injected workflow context.")).toHaveLength(1);
    expect(prompts.filter((prompt) => prompt.parts[0].text.includes("# native-edit"))).toHaveLength(2);

    prompts.length = 0;
    const retryNow = Date.now();
    const retryPart = {
      ...part,
      id: "part-retry",
      sessionID: "session-retry",
      callID: "call-retry",
      state: { ...part.state, time: { start: retryNow, end: retryNow + 10_000 } },
    };
    history = [{ info: {}, parts: [retryPart] }];
    historyFailures = 1;
    historyDelay = 20;
    await hooks["chat.message"]!({ sessionID: "session-retry" } as never, {} as never);
    const failedHydration = event({ event: { type: "session.status", properties: { sessionID: "session-retry" } } } as never);
    await event({ event: { type: "message.part.updated", properties: { part: retryPart } } } as never);
    const retriedAtIdle = event({ event: { type: "session.idle", properties: { sessionID: "session-retry" } } } as never);
    await Promise.all([failedHydration, retriedAtIdle]);
    historyDelay = 0;
    expect(prompts.filter((prompt) => prompt.parts[0].text === "Continue with the injected workflow context.")).toHaveLength(1);

    prompts.length = 0;
    const historicalPart = { ...part, id: "part-historical", sessionID: "session-historical", callID: "call-historical" };
    history = [{ info: {}, parts: [historicalPart] }];
    historyDelay = 20;
    await hooks["chat.message"]!({ sessionID: "session-historical" } as never, {} as never);
    const historicalHydration = event({ event: { type: "session.status", properties: { sessionID: "session-historical" } } } as never);
    await event({ event: { type: "message.part.updated", properties: { part: historicalPart } } } as never);
    await historicalHydration;
    historyDelay = 0;
    await event({ event: { type: "session.idle", properties: { sessionID: "session-historical" } } } as never);
    expect(prompts.filter((prompt) => prompt.parts[0].text.includes("# native-edit"))).toHaveLength(1);
  });
});
