import { createActor, type AnyActorRef, type AnyStateMachine, type SnapshotFrom } from "xstate";

export type WorkflowEffect = {
  type: "renderSkills";
  skills: string[];
  reply: boolean;
};

export type WorkflowDefinition = {
  id: string;
  version: number;
  machine: AnyStateMachine;
};

export type WorkflowHost = {
  persist(snapshot: unknown): Promise<void>;
  renderSkills(skills: string[], reply: boolean): Promise<void>;
};

export function validateWorkflowDefinition(definition: WorkflowDefinition): void {
  const machine = definition.machine;
  const states = Object.values(machine.states);
  if (!definition.id || !Number.isInteger(definition.version) || definition.version < 1 ||
    states.length === 0 || states.length > 64 || typeof machine.config.initial !== "string") {
    throw new Error("Invalid workflow definition");
  }
  const initial = machine.states[machine.config.initial];
  if (!initial || machine.root.invoke.length || machine.root.after.length || machine.root.always) {
    throw new Error("Unsupported workflow graph");
  }
  const visited = new Set([initial]);
  const pending = [initial];
  let edges = 0;
  while (pending.length) {
    const state = pending.shift()!;
    if ((state.type !== "atomic" && state.type !== "final") || state.invoke.length || state.after.length || state.always ||
      (!state.transitions.size && state.type !== "final")) {
      throw new Error(`Unsupported or dead-end workflow state: ${state.key}`);
    }
    for (const transitions of state.transitions.values()) {
      for (const transition of transitions) {
        if (++edges > 256) throw new Error("Workflow graph exceeds transition limit");
        for (const target of transition.target ?? []) {
          if (!states.includes(target)) throw new Error("Workflow target is outside the machine");
          if (!visited.has(target)) {
            visited.add(target);
            pending.push(target);
          }
        }
      }
    }
  }
  if (visited.size !== states.length) throw new Error("Workflow contains unreachable states");
}

export class WorkflowRuntime {
  private actor: AnyActorRef;
  private effects: WorkflowEffect[] = [];
  private stopped = false;

  constructor(
    readonly definition: WorkflowDefinition,
    private readonly host: WorkflowHost,
    snapshot?: unknown,
  ) {
    validateWorkflowDefinition(definition);
    if (snapshot !== undefined) {
      const state = snapshot as Record<string, unknown>;
      if (!state || typeof state !== "object" || Array.isArray(state) || state.status !== "active" ||
        typeof state.value !== "string" || !Object.hasOwn(definition.machine.states, state.value) ||
        !state.context || typeof state.context !== "object" || Array.isArray(state.context) ||
        !state.children || typeof state.children !== "object" || Array.isArray(state.children) ||
        Object.keys(state.children).length > 0) {
        throw new Error("Invalid persisted workflow snapshot");
      }
    }
    const machine = definition.machine.provide({
      actions: {
        "temper.renderSkills": (_args: unknown, params: { skills: string[]; reply?: boolean }) => {
          this.effects.push({ type: "renderSkills", skills: params.skills, reply: params.reply ?? false });
        },
      },
    });
    this.actor = createActor(machine, snapshot === undefined ? undefined : { snapshot: snapshot as never });
  }

  async start(): Promise<void> {
    this.effects = [];
    this.actor.start();
    await this.flush();
  }

  async send(event: object): Promise<void> {
    this.effects = [];
    this.actor.send(event);
    await this.flush();
  }

  getSnapshot(): SnapshotFrom<AnyStateMachine> {
    return this.actor.getSnapshot();
  }

  getPersistedSnapshot(): unknown {
    return this.actor.getPersistedSnapshot();
  }

  stop(): void {
    this.stopped = true;
    this.effects = [];
    this.actor.stop();
  }

  private async flush(): Promise<void> {
    if (this.stopped) return;
    await this.host.persist(this.actor.getPersistedSnapshot());
    if (this.stopped) return;
    const effects = this.effects;
    this.effects = [];
    for (const effect of effects) {
      if (this.stopped) return;
      await this.host.renderSkills(effect.skills, effect.reply);
    }
  }
}
