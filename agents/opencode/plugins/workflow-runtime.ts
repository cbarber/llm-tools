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

export class WorkflowRuntime {
  private actor: AnyActorRef;
  private effects: WorkflowEffect[] = [];

  constructor(
    readonly definition: WorkflowDefinition,
    private readonly host: WorkflowHost,
    snapshot?: unknown,
  ) {
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
    this.actor.stop();
  }

  private async flush(): Promise<void> {
    await this.host.persist(this.actor.getPersistedSnapshot());
    const effects = this.effects;
    this.effects = [];
    for (const effect of effects) {
      await this.host.renderSkills(effect.skills, effect.reply);
    }
  }
}
