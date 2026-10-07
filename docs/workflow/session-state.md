# Shared work state and interview handoff

## Desired continuity

Bounded and design-bearing work need one shared thread across skills, agents,
sessions, branches, and review rounds. The record must survive context exhaustion
and shell cleanup. Refer to existing artifacts; do not turn it into a transcript.

These are research requirements, not an implemented storage contract:

| Field | Purpose |
| --- | --- |
| Work identity and repository identity | Find the same work after a session or branch changes |
| Current path and step | Resume at the earliest incomplete step |
| Objective and accepted criteria | Preserve what the implementation must satisfy |
| Resolved decisions and artifact references | Carry the agreement without repeating the interview |
| Open decisions and blockers | Separate questions from facts still being investigated |
| Gate state, authority, and applicable revision | Distinguish a draft, an agent verdict, and human approval of a specific artifact |
| Verification and review evidence | Link checks, findings, fixes, and remaining uncertainty |
| Branch/worktree/session references | Locate executions without using them as the work's sole identity |
| Next action and handoff context | Let a fresh agent continue without reconstructing the conversation |

Passing a check, receiving human design approval, and completing a stage are
different events. Approval must not silently carry across a changed contract.
Exact invalidation and transition rules remain to be designed.

## Storage research

The user leans toward a home-directory store keyed by **repository/work**.
Repository/branch is familiar but branches are mutable, reusable, and not
necessarily one-to-one with work. Numbering is a candidate, not a selected scheme.

Investigate:

- Repository identity across clones, worktrees, renamed remotes, and local-only repos.
- Work identity: tracker ID, allocated number, or opaque unique ID with a readable label.
- Concurrent creation and updates: collision-safe allocation, ownership, and stale writes.
- One work item with multiple executions, and branches carrying multiple items.
- Discovery on resume without guessing from the branch name.
- Retention, relocation, permissions, and references to deleted temporary artifacts.
- Minimal CLI hooks that read/write the record without requiring an FSM.

Existing references are comparators, not adopted implementations:

- Installed Matt-derived `handoff` writes to OS-temporary storage; its durable
  replacement needs an explicit policy change.
- The [HumanLayer OpenCode integration](https://github.com/humanlayer/humanlayer-opencode/blob/main/README.md#what-it-does)
  exposes `.humanlayer/tasks/<slug>` in the repository as a link to task files
  backed by `~/.humanlayer/riptide/artifacts/`. It can attach later sessions to a
  task ID or slug. Task selection uses explicit attachment, an environment hint,
  or an unambiguous existing worktree task link before creating a session-named
  task. This is a concrete external-store comparator; its allocation and collision
  guarantees have not been verified here. The implementation skill also describes
  a task-directory symlink backed by another repository.
- Current [Temper](../../agents/opencode/plugins/temper.ts) stores session-hashed
  snapshots/traces under `$XDG_STATE_HOME/opencode/temper/`, falling back to
  `~/.local/state/opencode/temper/`. Session identity does not establish shared work identity.
- The previously investigated Bryson CLI is unrelated to Dex Horthy. Any storage
  mechanism borrowed from it needs a fresh source check, not Horthy attribution.

## Interview state: 2026-10-06

**Settled**

- Keep bounded and design-bearing paths; qualify rather than pretend to quantify risk.
- Use Matt and Dex as primary workflow references; retain poteto's stability proof approach.
- Include an implementation/review correction cycle. Keep consequential decisions human-owned.
- Preserve binding Mojo policy and final human review/stamping.
- Store this research in `docs/workflow.md` and supporting files.
- Exclude maintenance/debt registers; use linked follow-up tickets for concrete concerns.
- Aggregate small attributed rules; keep disagreements and uncategorized material visible.

**Direction, not final design**

- Agent routing can identify consequential unresolved choices and escalate them.
- Reviewer-proposed patches/fixups can be accepted by the owner; design-changing
  corrections should return to the human. Exact authority and loop limits remain open.
- Sequential handoffs should reduce manual context management before the “dumb zone.”
- Durable repository/work state should connect both paths; naming and collision handling need research.

**Next frontier**

Investigate work-store identity/concurrency and compare Matt's integrated task
graph with the desired sequential skill handoffs; then calibrate routing, approvals,
and verification on actual bounded and design-bearing changes. No runtime,
skill-chain replacement, or FSM rollback has been authorized by this document.
