import { describe, expect, test } from "bun:test";
import { setup } from "xstate";
import { WorkflowRuntime } from "./workflow-runtime";

const workflowUrl = new URL("../../skills/mojo-init/workflow.ts", import.meta.url).href;
const { workflow: source } = await import(workflowUrl);
const workflow = { id: source.id, version: source.version, machine: source.createMachine(setup) };
const clean = { dirty: false, head: "a", ahead: 0, hasPr: false };

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
      after: { ...clean, head: "b", ahead: 1 },
    });
    expect(deliveries.at(-1)).toEqual({ skills: ["mojo-edit-nudge"], reply: false });

    await runtime.send({ type: "idle.elapsed", facts: { ...clean, head: "b", ahead: 1 } });
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
});
