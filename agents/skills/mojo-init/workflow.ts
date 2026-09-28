export type MojoFacts = {
  dirty: boolean;
  head: string;
  ahead: number;
  hasPr: boolean;
  prHead?: string;
  merged?: boolean;
  authorApprovalRequired?: boolean;
};

type MojoEvent =
  | { type: "tool.finished"; tool: string; before: MojoFacts; after: MojoFacts }
  | { type: "idle.elapsed"; facts: MojoFacts }
  | { type: "external.chat"; facts: MojoFacts };

const isEdit = ({ event }: { event: MojoEvent }) =>
  event.type === "tool.finished" && ["apply_patch", "edit", "write"].includes(event.tool);

const observedCleanCommit = ({ event }: { event: MojoEvent }) =>
  event.type === "tool.finished" && event.before.head !== event.after.head && !event.after.dirty;

const dirty = ({ event }: { event: MojoEvent }) =>
  event.type === "idle.elapsed" && event.facts.dirty;

const needsPr = ({ event }: { event: MojoEvent }) =>
  event.type === "idle.elapsed" && !event.facts.dirty && event.facts.ahead > 0 && !event.facts.hasPr;

const needsPush = ({ event }: { event: MojoEvent }) =>
  event.type === "idle.elapsed" && !event.facts.dirty && event.facts.ahead > 0 && event.facts.hasPr;

const createMachine = (setup: typeof import("xstate").setup) => setup({
  types: {
    events: {} as MojoEvent,
  },
  actions: {
    "temper.renderSkills": (_args: unknown, _params: { skills: string[]; reply?: boolean }) => {},
  },
  guards: { isEdit, observedCleanCommit, dirty, needsPr, needsPush },
}).createMachine({
  id: "mojo",
  initial: "active",
  entry: {
    type: "temper.renderSkills",
    params: { skills: ["mojo-init", "mojo-edit-nudge"] },
  },
  states: {
    active: {
      on: {
        "tool.finished": [
          {
            guard: "observedCleanCommit",
            actions: {
              type: "temper.renderSkills",
              params: { skills: ["mojo-edit-nudge"] },
            },
          },
          { guard: "isEdit", target: "changeInProgress" },
        ],
        "idle.elapsed": [
          {
            guard: "dirty",
            target: "commitRequested",
            actions: { type: "temper.renderSkills", params: { skills: ["mojo-commit"], reply: true } },
          },
          {
            guard: "needsPr",
            target: "publicationRequested",
            actions: { type: "temper.renderSkills", params: { skills: ["mojo-create-pull-request"], reply: true } },
          },
          {
            guard: "needsPush",
            target: "publicationRequested",
            actions: { type: "temper.renderSkills", params: { skills: ["mojo-update-pull-request"], reply: true } },
          },
        ],
      },
    },
    changeInProgress: {
      on: {
        "tool.finished": {
          guard: "observedCleanCommit",
          target: "active",
          actions: {
            type: "temper.renderSkills",
            params: { skills: ["mojo-edit-nudge"] },
          },
        },
        "idle.elapsed": {
          guard: "dirty",
          target: "commitRequested",
          actions: { type: "temper.renderSkills", params: { skills: ["mojo-commit"], reply: true } },
        },
      },
    },
    commitRequested: {
      on: {
        "tool.finished": {
          guard: "observedCleanCommit",
          target: "active",
          actions: {
            type: "temper.renderSkills",
            params: { skills: ["mojo-edit-nudge"] },
          },
        },
      },
    },
    publicationRequested: {
      on: {
        "tool.finished": { guard: "isEdit", target: "changeInProgress" },
        "external.chat": { target: "active" },
      },
    },
  },
});

export const workflow = {
  id: "mojo",
  version: 1,
  createMachine,
};
