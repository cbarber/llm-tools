import { describe, expect, test } from "bun:test";
import { setup } from "xstate";
import { WorkflowRuntime, validateWorkflowDefinition, type WorkflowDefinition } from "./workflow-runtime";

const workflowUrl = new URL("../../skills/mojo-init/workflow.ts", import.meta.url).href;
const { workflow: source } = await import(workflowUrl);
const workflow = { id: source.id, version: source.version, machine: source.createMachine(setup) };
const clean = { dirty: false, head: "a", ahead: 0, branchCommits: 0, hasPr: false };

describe("Mojo workflow runtime", () => {
  test("steers activation, one change cycle, and publication", async () => {
    const deliveries: Array<{ skills: string[]; reply: boolean }> = [];
    const snapshots: unknown[] = [];
    const runtime = new WorkflowRuntime(workflow, {
      persist: async (snapshot) => { snapshots.push(snapshot); },
      renderSkills: async (skills, reply) => { deliveries.push({ skills, reply }); },
    });

    await runtime.start();
    expect(deliveries).toEqual([{ skills: ["mojo-init", "mojo-edit-nudge"], reply: false }]);

    await runtime.send({ type: "tool.finished", tool: "apply_patch", before: clean, after: { ...clean, dirty: true } });
    await runtime.send({ type: "tool.finished", tool: "edit", before: { ...clean, dirty: true }, after: { ...clean, dirty: true } });
    expect(deliveries).toHaveLength(1);

    await runtime.send({
      type: "tool.finished",
      tool: "bash",
      before: { ...clean, dirty: true },
      after: { ...clean, head: "b", ahead: 1, branchCommits: 1 },
    });
    expect(deliveries.at(-1)).toEqual({ skills: ["mojo-edit-nudge"], reply: false });

    await runtime.send({ type: "idle.elapsed", facts: { ...clean, head: "b", ahead: 1, branchCommits: 1 } });
    expect(deliveries.at(-1)).toEqual({ skills: ["mojo-create-pull-request"], reply: true });
    expect(snapshots.length).toBeGreaterThanOrEqual(5);
  });

  test("persists a transition before delivering its effect", async () => {
    const order: string[] = [];
    const runtime = new WorkflowRuntime(workflow, {
      persist: async () => { order.push("persist"); },
      renderSkills: async () => { order.push("deliver"); },
    });

    await runtime.start();
    expect(order).toEqual(["persist", "deliver"]);
  });

  test("requests a PR for pushed branch commits", async () => {
    const deliveries: string[][] = [];
    const runtime = new WorkflowRuntime(workflow, {
      persist: async () => {},
      renderSkills: async (skills) => { deliveries.push(skills); },
    });
    await runtime.start();
    await runtime.send({
      type: "idle.elapsed",
      facts: { ...clean, ahead: 0, branchCommits: 1, hasPr: false },
    });
    expect(deliveries.at(-1)).toEqual(["mojo-create-pull-request"]);
  });

  test("ignores pre-existing dirt and publishes commits with unrelated untracked files", async () => {
    const deliveries: string[][] = [];
    const runtime = new WorkflowRuntime(workflow, {
      persist: async () => {},
      renderSkills: async (skills) => { deliveries.push(skills); },
    });
    const unrelated = { ...clean, dirty: true, hasPr: true };
    await runtime.start();
    await runtime.send({ type: "idle.elapsed", facts: unrelated });
    expect(deliveries).toHaveLength(1);

    await runtime.send({ type: "tool.finished", tool: "apply_patch", before: unrelated, after: unrelated });
    await runtime.send({ type: "idle.elapsed", facts: unrelated });
    expect(deliveries.at(-1)).toEqual(["mojo-commit"]);

    const committed = { ...unrelated, head: "b", ahead: 1, branchCommits: 1 };
    await runtime.send({ type: "tool.finished", tool: "bash", before: unrelated, after: committed });
    await runtime.send({ type: "idle.elapsed", facts: committed });
    expect(deliveries.at(-1)).toEqual(["mojo-update-pull-request"]);

    const published = { ...committed, ahead: 0 };
    await runtime.send({ type: "tool.finished", tool: "bash", before: committed, after: published });
    expect(runtime.getSnapshot().value).toBe("awaitingTeamFeedback");
  });

  test("waits for author approval and responds to review feedback", async () => {
    const deliveries: string[][] = [];
    const runtime = new WorkflowRuntime(workflow, {
      persist: async () => {},
      renderSkills: async (skills) => { deliveries.push(skills); },
    });
    await runtime.start();
    const unpublished = { ...clean, head: "b", branchCommits: 1, ahead: 1 };
    await runtime.send({ type: "idle.elapsed", facts: unpublished });
    const published = { ...unpublished, hasPr: true, ahead: 0, authorApprovalRequired: true };
    await runtime.send({ type: "tool.finished", tool: "bash", before: unpublished, after: published });
    const count = deliveries.length;
    await runtime.send({ type: "idle.elapsed", facts: published });
    expect(deliveries).toHaveLength(count);

    await runtime.send({ type: "external.chat", facts: { ...published, reviewDecision: "CHANGES_REQUESTED" } });
    expect(deliveries.at(-1)).toEqual(["mojo-review-response"]);
    await runtime.send({ type: "idle.elapsed", facts: published });
    expect(deliveries).toHaveLength(count + 1);
  });

  test("returns waiting ownership to the agent on external chat", async () => {
    const deliveries: string[][] = [];
    const runtime = new WorkflowRuntime(workflow, {
      persist: async () => {},
      renderSkills: async (skills) => { deliveries.push(skills); },
    });
    await runtime.start();
    const published = { ...clean, hasPr: true, branchCommits: 1 };
    await runtime.send({ type: "idle.elapsed", facts: published });
    await runtime.send({ type: "external.chat", facts: published });
    await runtime.send({ type: "tool.finished", tool: "apply_patch", before: published, after: { ...published, dirty: true } });
    await runtime.send({ type: "idle.elapsed", facts: { ...published, dirty: true } });
    expect(deliveries.at(-1)).toEqual(["mojo-commit"]);
  });

  test("restores without replaying effects", async () => {
    let snapshot: unknown;
    const runtime = new WorkflowRuntime(workflow, {
      persist: async (value) => { snapshot = JSON.parse(JSON.stringify(value)); },
      renderSkills: async () => {},
    });
    await runtime.start();
    await runtime.send({ type: "idle.elapsed", facts: { ...clean, dirty: true } });

    const deliveries: string[][] = [];
    const restored = new WorkflowRuntime(workflow, {
      persist: async () => {},
      renderSkills: async (skills) => { deliveries.push(skills); },
    }, snapshot);
    await restored.start();
    expect(deliveries).toEqual([]);
  });

  test("stopping during persistence prevents delivery", async () => {
    let release!: () => void;
    const blocked = new Promise<void>((resolve) => { release = resolve; });
    const deliveries: string[][] = [];
    const runtime = new WorkflowRuntime(workflow, {
      persist: async () => { await blocked; },
      renderSkills: async (skills) => { deliveries.push(skills); },
    });
    const starting = runtime.start();
    runtime.stop();
    release();
    await starting;
    expect(deliveries).toEqual([]);
  });

  test("rejects corrupted persisted states before starting an actor", () => {
    const host = { persist: async () => {}, renderSkills: async () => {} };
    expect(() => new WorkflowRuntime(workflow, host, { status: "active", value: "missing", context: {}, children: {} })).toThrow();
    expect(() => new WorkflowRuntime(workflow, host, { status: "active", value: "active", context: {}, children: { child: {} } })).toThrow();
    expect(() => new WorkflowRuntime(workflow, host, { status: "active", value: "active", context: null, children: {} })).toThrow();
  });

  test("rejects unreachable, dead-end, and delayed workflow states", () => {
    const machine = (states: Record<string, unknown>) => ({
      id: "fixture", version: 1, machine: setup({}).createMachine({ initial: "start", states } as never) as unknown as WorkflowDefinition["machine"],
    });
    expect(() => validateWorkflowDefinition(machine({ start: { on: { NEXT: "end" } }, end: {} }))).toThrow();
    expect(() => validateWorkflowDefinition(machine({ start: { on: { NEXT: "start" } }, unused: { on: { NEXT: "start" } } }))).toThrow();
    expect(() => validateWorkflowDefinition(machine({ start: { after: { 1000: "start" }, on: { NEXT: "start" } } }))).toThrow();
  });
});
