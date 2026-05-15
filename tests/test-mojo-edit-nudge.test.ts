
import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import { writeFile } from "node:fs/promises";
import type { MockServer, RequestHistory } from "llm-mock-server";
import { rm } from "node:fs/promises";
import { createFixtureRepo, createSession, findFreePort, sendPromptAndWait, startOpencode, writeOpencodeConfig } from "./harness"

// ---------------------------------------------------------------------------
// mojo-edit-nudge: fail action blocks the first edit and delivers nudge text
// ---------------------------------------------------------------------------

let nudgeMock: MockServer;
let nudgeHistory: RequestHistory;
let stopNudgeOpencode: () => void;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  nudgeMock = await createMock({ port: mockPort, logLevel: "none" });

  nudgeMock.when((req) => req.toolNames.length === 0).reply("Test session title");

  // Scripted workflow for fail action test:
  //   Turn 1: model calls edit
  //            → mojo-edit-nudge fires on tool.execute.before, throws
  //            → edit is blocked; model receives tool error with nudge content
  //   Turn 2: model calls edit again (retry after seeing nudge)
  //            → mojo-edit-nudge already fired (once:true); edit proceeds
  //   Turn 3: model replies done
  nudgeMock.when((req) => req.toolNames.length > 0).replySequence([
    {
      reply: {
        tools: [{
          name: "edit",
          args: {
            filePath: "/tmp/test.txt",
            oldString: "hello",
            newString: "hello world",
          },
        }],
      },
    },
    {
      reply: {
        tools: [{
          name: "edit",
          args: {
            filePath: "/tmp/test.txt",
            oldString: "hello",
            newString: "hello world",
          },
        }],
      },
    },
    { reply: { text: "Done." } },
    { reply: { text: "All done." } },
  ]);

  const dir = await createFixtureRepo();
  // Create the file the edit tool will target
  await writeFile("/tmp/test.txt", "hello\n");
  await writeOpencodeConfig(dir, `${nudgeMock.url}/v1`);

  stopNudgeOpencode = (await startOpencode(dir, ocPort)).stop;

  const sessionID = await createSession(ocPort, dir);
  await sendPromptAndWait(ocPort, sessionID, "Update the test file.", nudgeMock);

  nudgeHistory = nudgeMock.history;

  await rm(dir, { recursive: true, force: true }).catch(() => { });
}, 90_000);

afterAll(async () => {
  stopNudgeOpencode?.();
  await nudgeMock?.stop();
});

describe("temper plugin — mojo-edit-nudge fail action", () => {
  function taskRequests() {
    return nudgeHistory.all.filter(
      (e) => !e.request.systemMessage.includes("title generator")
    );
  }

  it("blocks the first edit and delivers nudge as tool error", () => {
    // The fail action throws in tool.execute.before. OpenCode surfaces the
    // thrown message as the tool result, so the model sees the nudge content
    // instead of "Edit applied successfully."
    const tasks = taskRequests();
    expect(tasks.length).toBeGreaterThanOrEqual(2);
    const messages = tasks[1].request.messages;
    const nudgeToolMessages = messages.filter(
      (m) => m.role === "tool" && m.content.includes("# mojo-edit-nudge")
    );
    expect(nudgeToolMessages.length).toBe(1);
    const editSucceeded = messages.some(
      (m) => m.role === "tool" && m.content.includes("Edit applied successfully.")
    );
    expect(editSucceeded).toBe(false);
  });

  it("fires nudge exactly once across two edits and lets the second through", () => {
    // once:true ensures firedOnce blocks the second fire. The nudge appears
    // exactly once as a tool message across the full conversation, and the
    // second edit produces "Edit applied successfully." not another nudge.
    const tasks = taskRequests();
    expect(tasks.length).toBeGreaterThanOrEqual(3);
    const allMessages = tasks[2].request.messages;
    const nudgeCount = allMessages.filter(
      (m) => m.role === "tool" && m.content.includes("# mojo-edit-nudge")
    ).length;
    expect(nudgeCount).toBe(1);
    const secondEditSucceeded = allMessages.some(
      (m) => m.role === "tool" && m.content.includes("Edit applied successfully.")
    );
    expect(secondEditSucceeded).toBe(true);
  });
});
