import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer } from "llm-mock-server";
import { rm } from "node:fs/promises";
import {
  createFixtureRepo,
  createSession,
  findFreePort,
  sendPromptAndWait,
  startOpencode,
  writeOpencodeConfig,
} from "./harness";

describe("temper command events", () => {
  let stopOpencode: () => void;
  let mock: MockServer;
  let dir: string;

  beforeAll(async () => {
    const mockPort = await findFreePort();
    const ocPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");
    mock.when((req) => req.toolNames.length > 0).replySequence([
      { reply: { tools: [{ name: "bash", args: { command: "false # forge pr create" } }] } },
      { reply: { text: "Command failed." } },
      { reply: { tools: [{ name: "bash", args: { command: "git rebase --abort" } }] } },
      { reply: { text: "Done." } },
    ]);

    dir = await createFixtureRepo();
    await writeOpencodeConfig(dir, `${mock.url}/v1`);

    ({ stop: stopOpencode } = await startOpencode(dir, ocPort));
    const sessionID = await createSession(ocPort, dir);
    await sendPromptAndWait(ocPort, sessionID, "Run the failing command.", mock);
    await sendPromptAndWait(ocPort, sessionID, "Run the rebase command.", mock);
  }, 90_000);

  afterAll(async () => {
    stopOpencode?.();
    await mock?.stop();
    await rm(dir, { recursive: true, force: true }).catch(() => { });
  });

  it("does not dispatch after failed commands", () => {
    const requests = mock.history.all.filter((entry) => entry.request.toolNames.length > 0);
    expect(requests.some((entry) => entry.request.messages.some((message) => message.content.includes("# mojo-pull-request")))).toBeFalse();
  });

  it("matches command regexes before execution", () => {
    const request = mock.history.all.filter((entry) => entry.request.toolNames.length > 0).at(-1)!.request;
    expect(request.messages.some((message) => message.content.includes("# mojo-rebase"))).toBeTrue();
  });
});
