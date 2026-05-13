import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { createMock } from "llm-mock-server";
import type { MockServer } from "llm-mock-server";
import { rm } from "node:fs/promises";
import {
  createFixtureRepo,
  createSession,
  findFreePort,
  restartOpencode,
  sendPromptAndWait,
  startOpencode,
  verifySession,
  writeOpencodeConfig,
} from "./harness";

let mock: MockServer;
let stopOpencode: () => void;
let sessionID: string;
let countAfterFirstPrompt: number;
let countAfterRestart: number;

beforeAll(async () => {
  const mockPort = await findFreePort();
  const ocPort = await findFreePort();

  mock = await createMock({ port: mockPort, logLevel: "none" });

  mock.when((req) => req.toolNames.length === 0).reply("Test session title");
  mock.when((req) => req.toolNames.length > 0).reply("Done.");

  const dir = await createFixtureRepo();
  await writeOpencodeConfig(dir, `${mock.url}/v1`);

  stopOpencode = await startOpencode(dir, ocPort);
  sessionID = await createSession(ocPort, dir);

  await sendPromptAndWait(ocPort, sessionID, "Hello before restart.", mock);
  countAfterFirstPrompt = mock.history.count();

  stopOpencode = await restartOpencode(stopOpencode, dir, ocPort);

  await verifySession(ocPort, sessionID);
  countAfterRestart = mock.history.count();

  await sendPromptAndWait(ocPort, sessionID, "Hello after restart.", mock);

  await rm(dir, { recursive: true, force: true }).catch(() => {});
}, 120_000);

afterAll(async () => {
  stopOpencode?.();
  await mock?.stop();
});

describe("harness — restartOpencode", () => {
  it("session is accessible after restart (verifySession resolves)", () => {
    // verifySession threw in beforeAll if it failed; reaching here means it passed
    expect(sessionID).toBeTruthy();
  });

  it("second prompt after restart produces new mock requests", () => {
    expect(mock.history.count()).toBeGreaterThan(countAfterRestart);
  });

  it("mock received requests for both prompts", () => {
    expect(countAfterFirstPrompt).toBeGreaterThan(0);
    expect(mock.history.count()).toBeGreaterThan(countAfterFirstPrompt);
  });
});
