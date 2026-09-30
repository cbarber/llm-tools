import { describe, expect, test } from "bun:test";

const completed = (callID: string, tool: string, input: Record<string, unknown> = {}, id = callID) => ({
  id,
  type: "tool",
  callID,
  tool,
  metadata: { providerExecuted: true },
  state: {
    status: "completed",
    input,
    title: tool,
    output: "ok",
    metadata: {},
  },
});

const replay = (parts: Array<{ restore?: boolean; part: unknown }>) => {
  const result = Bun.spawnSync(["bun", "temper.ts", "--provider-tools", JSON.stringify(parts), "", "/worktree"], {
    cwd: import.meta.dir,
  });
  expect(result.exitCode).toBe(0);
  return JSON.parse(result.stdout.toString());
};

describe("ProviderToolQueue", () => {
  test("queues each completed provider tool once and drains at idle", () => {
    const shell = completed("call-shell", "bash", { command: "git status" });
    const edit = completed("call-edit", "edit", { filePath: "src/main.ts" });

    expect(replay([{ part: shell }, { part: shell }, { part: edit }])).toEqual({
      updates: [true, false, true],
      pending: [
        {
          event: "tool.execute.after",
          tool: "bash",
          command: "git status",
          filePaths: [],
          output: { title: "bash", output: "ok", metadata: {} },
        },
        {
          event: "tool.execute.after",
          tool: "edit",
          command: "",
          filePaths: ["/worktree/src/main.ts"],
          output: { title: "edit", output: "ok", metadata: {} },
        },
      ],
    });
  });

  test("ignores non-terminal and host-executed parts", () => {
    const running = completed("call-running", "read", { filePath: "README.md" });
    running.state.status = "running";
    const host = completed("call-host", "read", { filePath: "README.md" });
    host.metadata.providerExecuted = false;

    expect(replay([{ part: running }, { part: host }])).toEqual({ updates: [false, false], pending: [] });
  });

  test("restored and errored calls cannot replay", () => {
    const restored = completed("call-restored", "edit", { filePath: "old.ts" });
    const failed = completed("call-failed", "edit", { filePath: "failed.ts" });
    failed.state.status = "error";

    expect(replay([
      { restore: true, part: restored },
      { part: restored },
      { part: failed },
      { part: failed },
    ])).toEqual({ updates: [false, false, false, false], pending: [] });
  });

  test("allows a later message to reuse a provider call ID", () => {
    const first = completed("call-edit", "edit", { filePath: "first.ts" }, "part-first");
    const second = completed("call-edit", "edit", { filePath: "second.ts" }, "part-second");

    expect(replay([{ part: first }, { part: second }]).updates).toEqual([true, true]);
  });
});
