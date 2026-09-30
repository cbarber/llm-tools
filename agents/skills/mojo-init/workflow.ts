import type { setup as xstateSetup } from "xstate";

export type MojoFacts = {
  dirty: boolean;
  head: string;
  ahead: number;
  branchCommits: number;
  hasPr: boolean;
  prHead?: string;
  merged?: boolean;
  authorApprovalRequired?: boolean;
  reviewDecision?: string;
};

type MojoEvent =
  | { type: "tool.finished"; tool: string; before: MojoFacts; after: MojoFacts }
  | { type: "idle.elapsed"; facts: MojoFacts }
  | { type: "external.chat"; facts: MojoFacts };

const isEdit = ({ event }: { event: MojoEvent }) =>
  event.type === "tool.finished" && ["apply_patch", "edit", "write"].includes(event.tool);

const observedCleanCommit = ({ event }: { event: MojoEvent }) =>
  event.type === "tool.finished" && event.before.head !== event.after.head;

const dirty = ({ event }: { event: MojoEvent }) =>
  event.type === "idle.elapsed" && event.facts.dirty;

const needsPr = ({ event }: { event: MojoEvent }) =>
  event.type === "idle.elapsed" && !event.facts.dirty && event.facts.branchCommits > 0 && !event.facts.hasPr;

const needsPush = ({ event }: { event: MojoEvent }) =>
  event.type === "idle.elapsed" && event.facts.ahead > 0 && event.facts.hasPr;

const awaitingAuthor = ({ event }: { event: MojoEvent }) =>
  "facts" in event && event.facts.hasPr && event.facts.ahead === 0 && event.facts.authorApprovalRequired === true;

const awaitingTeam = ({ event }: { event: MojoEvent }) =>
  "facts" in event && event.facts.hasPr && event.facts.ahead === 0 && !event.facts.authorApprovalRequired;

const publishedForAuthor = ({ event }: { event: MojoEvent }) =>
  event.type === "tool.finished" && event.after.hasPr && event.after.ahead === 0 && event.after.authorApprovalRequired === true;

const publishedForTeam = ({ event }: { event: MojoEvent }) =>
  event.type === "tool.finished" && event.after.hasPr && event.after.ahead === 0 && !event.after.authorApprovalRequired;

const feedback = ({ event }: { event: MojoEvent }) =>
  event.type === "external.chat" && event.facts.reviewDecision === "CHANGES_REQUESTED";

const createMachine = (setup: typeof xstateSetup) => setup({
  types: {
    events: {} as MojoEvent,
  },
  actions: {
    "temper.renderSkills": (_args: unknown, _params: { skills: string[]; reply?: boolean }) => {},
  },
  guards: { isEdit, observedCleanCommit, dirty, needsPr, needsPush, awaitingAuthor, awaitingTeam, publishedForAuthor, publishedForTeam, feedback },
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
            guard: "needsPr",
            target: "publicationRequested",
            actions: { type: "temper.renderSkills", params: { skills: ["mojo-create-pull-request"], reply: true } },
          },
          {
            guard: "needsPush",
            target: "publicationRequested",
            actions: { type: "temper.renderSkills", params: { skills: ["mojo-update-pull-request"], reply: true } },
          },
          { guard: "awaitingAuthor", target: "awaitingAuthorApproval" },
          { guard: "awaitingTeam", target: "awaitingTeamFeedback" },
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
        "tool.finished": [
          { guard: "isEdit", target: "changeInProgress" },
          { guard: "publishedForAuthor", target: "awaitingAuthorApproval" },
          { guard: "publishedForTeam", target: "awaitingTeamFeedback" },
        ],
        "external.chat": { target: "active" },
      },
    },
    awaitingAuthorApproval: {
      on: {
        "tool.finished": { guard: "publishedForTeam", target: "awaitingTeamFeedback" },
        "external.chat": [
          { guard: "feedback", target: "active", actions: { type: "temper.renderSkills", params: { skills: ["mojo-review-response"] } } },
          { target: "active" },
        ],
      },
    },
    awaitingTeamFeedback: {
      on: {
        "tool.finished": { guard: "isEdit", target: "changeInProgress" },
        "external.chat": [
          { guard: "feedback", target: "active", actions: { type: "temper.renderSkills", params: { skills: ["mojo-review-response"] } } },
          { target: "active" },
        ],
      },
    },
  },
});

export const workflow = {
  id: "mojo",
  version: 1,
  createMachine,
};
