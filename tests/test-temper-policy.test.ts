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

describe("temper policy", () => {
  let stopOpencode: () => void;
  let mock: MockServer;
  let dir: string;

  beforeAll(async () => {
    const mockPort = await findFreePort();
    const ocPort = await findFreePort();

    mock = await createMock({ port: mockPort, logLevel: "none" });
    mock.when((req) => req.toolNames.length === 0).reply("Test session title");
    mock.when((req) => req.toolNames.length > 0).reply("Done.");

    dir = await createFixtureRepo();
    await writeOpencodeConfig(dir, `${mock.url}/v1`);

    ({ stop: stopOpencode } = await startOpencode(dir, ocPort));
    const sessionID = await createSession(ocPort, dir);
    await sendPromptAndWait(ocPort, sessionID, "Inspect the repository.", mock);
  }, 90_000);

  afterAll(async () => {
    stopOpencode?.();
    await mock?.stop();
    await rm(dir, { recursive: true, force: true }).catch(() => { });
  });

  it("removes OpenCode Git workflow instructions", () => {
    const request = mock.history.all.find((entry) => entry.request.toolNames.length > 0)!.request;
    const bash = request.tools?.find((tool) => tool.name === "bash");

    expect(request.systemMessage).not.toContain("NEVER commit changes unless the user explicitly asks");
    expect(bash?.description).not.toContain("# Git and GitHub");
    expect(bash?.description).toContain("Executes a given bash command");
  });
});
