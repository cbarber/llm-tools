# Claude workflow program design

Status: implementation target distilled from the grilling. The selected behavior
is defined in [decisions](decisions.md) and [architecture](architecture.md).
Exact command names, storage naming, and tuning are implementation details;
the example interfaces below are descriptive, not existing APIs.

## Compose native skills, a small record helper, and terminal transport

| Piece | Concrete responsibility |
| --- | --- |
| Design/spec/ticket skills | Adapt Pocock interviewing/decomposition and Dex design guidance to the selected flow. |
| Implementation entry/coordinator | Execute sequential tickets; dispatch fresh implementers/reviewers; reconcile proposals; record progress. |
| Worker role instructions | Front-load task/design references, Mojo discipline, and applicable style skills. |
| Review entry | Fresh artifact/contract review; produce findings and optional SHA-targeted fixup proposals. |
| Handoff/resume entry | Write reasoned handoff; reload applicable instructions and current-work references after renewal. |
| Work-record helper | Read/update the small JSON record and expose a continuation check. |
| Stop hook | Nudge approved remaining work; allow human gates and completed agent work to stop. |
| Herdr renewal integration | Compact the current pane after handoff readiness, confirm renewal, then submit resume entry. |

Use existing native mechanisms before adding glue. There is no custom executable
Markdown renderer, transcript parser, worker fleet manager, or independent workflow
framework in this plan.

## Claude renders executable skill initialization

Herdr submits an entry/resume skill invocation to the current pane. Claude loads
and renders that skill. Adapt Mojo's current `{exec}` convention to Claude's
documented inline `!` commands or fenced executable blocks:

````markdown
```!
git status --short --branch
```
````

Native executable context supplies initialization facts before the model receives
the instructions. Do not execute ordinary code examples or build another standard.
Commands must use the assigned repository/worktree context. Verify native behavior
on the installed Claude version and under the existing sandbox.

### Entry loads the applicable instructions

```text
coordinator entry
  selected workflow instructions
  Mojo initialization
  active work record and artifact references

implementer entry
  assigned ticket and approved design
  Mojo initialization, edit discipline, and commit/history guidance
  repository conventions and applicable personal language-style skills

reviewer/fixup-author entry
  artifact and agreed contract in fresh context
  applicable repository/language guidance
  Mojo initialization/edit/commit guidance when proposing changes
```

Use Claude's native Agent/skill mechanisms for subagents. A separate reviewer
session is also permitted. Do not use a fork inheriting the author conversation
when fresh review is required. Validate executable initialization and skill loading
for the chosen worker mechanism; do not assume that a skill reference alone runs
its commands.

Personal language-style skills hold reusable preferences. Repository instructions,
formatter/linter/compiler configuration, and established local patterns govern
local conventions. Select relevant guidance at entry, rather than load every
language's style or inject it at each edit. Reference authoritative Mojo content
instead of duplicating its policy in every role.

### Initialization no longer asks Forge to infer the workflow

Adapt `mojo-init` to identify agent/sandbox, inspect Git state, and load active work.
Remove routine `forge pr status` / `forge pr next-action` from this workflow's
entry initialization. Invoke Forge for relevant external review feedback and PR
publication/update/state checks at their actual steps. The work record supplies
the workflow's current action.

## One work.json is the operational cursor

Store `work.json` in a durable home-directory work folder. The active session
points to that record. Use an existing spec/issue identity where available;
repository/work directory naming and the local-only fallback are implementation
details, not a reason to introduce a larger identity service.

| Agreed content | Use |
| --- | --- |
| Current ticket and next action | Find the interrupted action or next unblocked ticket. |
| Pending human gate, if any | Preserve deliberate stops through continuation and compaction. |
| Correction-round count | Preserve the three-round bound for the current ticket or final review. |
| Branch | Find the implementation or relevant agent work. |
| Artifact reference links | Design, spec, tickets, reports, and reasoned handoff. |
| Agent/tool/session IDs | Retrieve historical context through existing tooling when needed. |

Do not add Herdr pane references, commit ranges, or transcript paths. Exact JSON
key names are left to implementation. Keep reference content in the referenced
artifact. SHA-targeted fixup details belong in proposal reports and Git, not an
expanded continuation index.

The coordinator advances progress after inspecting results. Workers return reports.
Use complete, atomic file updates so Stop cannot read a partially written record.
Missing or inconsistent state pauses for reconciliation rather than inventing
progress. A native task list can display progress but is not the only durable record.

Descriptive helper seams:

```text
read active work → current record
record reconciled outcome → updated record
check continuation(record) → continue | wait for human | agent work complete
```

Keep context metrics and renewal transport bookkeeping with the integration that
owns them; do not turn `work.json` into a terminal telemetry database.

## Implementation and review use reports as the handoff between roles

The coordinator dispatches the next unblocked ticket with artifact pointers, not
a pasted conversation. The implementer returns a report with the work performed,
verification evidence, and concerns. The coordinator checks the report against
actual Git/artifacts, then requests fresh review.

A review proposal identifies its finding, target SHA, fixup SHA, and supporting
checks in the report. Use an isolated proposal branch/worktree so rejection leaves
the active implementation checkout intact. The coordinator accepts or rejects
proposals, verifies accepted changes, and obtains fresh re-review.

Record each completed correction round durably. A round is proposal/reconciliation,
verification of accepted changes, and re-review. Rejected proposals do not establish
completion; unresolved substantive findings still count toward the bound. Neither
compaction nor changing reviewer resets the loop. New ticket/final-review scopes
have their own three-round counts.

Fold accepted fixups into owning commits before publication using Mojo tools.
Ensure later proposals target the current history after rewriting. Final human
review/stamping is separate from an agent's clean review verdict.

## Stop is a continuation nudge, not a policy loader

The coordinator normally continues in one active turn. Stop is an end-of-response
checkpoint, not an event after every tool call.

```text
on Stop
  read active work
  human gate pending? → allow stopping
  agent work complete? → allow final human review
  approved execution has remaining work? → request continuation from record
```

Use documented Stop decision control, for example a block reason that tells Claude
to continue the active workflow from its recorded next action. Do not inject the
engineering skill bodies at Stop or reinstate first-edit policy triggers.

Respect hook-continuation metadata and bound repeated nudges without progress.
The exact guard belongs to integration validation. Do not blindly copy a guard
that disables required follow-up checks, nor create an endless prompt-replay loop.
Grilling, design approval, and other human gates must not be treated as unfinished
approved execution. If an actual worker is still active, wait/reconcile it rather
than dispatch duplicate work.

## Renewal waits for a reasoned handoff and confirmed compaction

```text
context integration identifies renewal need
  → request reasoned handoff from main agent
  → confirm readiness, or pause for human
  → allow turn to settle
  → Herdr submits /compact to current pane
  → confirm actual compaction, not merely successful input delivery
  → submit native resume entry when ready
  → reload skills, work record, and handoff references
  → reconcile progress and continue only permitted work
```

Handoff readiness must relate to the current work; age/file existence alone is not
proof that an agreed decision or human gate was preserved. The main agent records
the reasoned handoff outcome. A mechanical PreCompact note can supplement it but
cannot authorize the rejected blind fallback.

The resume entry reuses the current pane. Capture agent/tool/session IDs through
native results/hooks as supported, and use existing session tooling for selective
historical context. No custom transcript reader is required. An old worker ID
is not automatically a valid continuation handle in a different parent session.

Validate the native auto-compaction interaction, Stop timing, readiness detection,
and completion observation before enabling the loop. If the handoff/renewal sequence
fails, preserve the work and stop for intervention. Do not silently change to
background-session launch, same-pane clear, or emergency blind compaction.

## Reuse existing integration mechanisms

These are researched candidates, not installed dependencies or adopted packages:

| Candidate | Useful mechanism | Required adaptation/validation |
| --- | --- | --- |
| [Herdr Context Meter](https://github.com/tmastalirsch/herdr-claude-context-meter) | Status-line context metrics associated with live Claude sessions. | Installed-version/session association and freshness. |
| [Compact Handoff](https://github.com/tmastalirsch/claude-compact-handoff) | Stop request, PreCompact mechanical facts, post-compact reference injection. | Current-work association, reasoned-note failure gate, native skill entry. |
| [Safe Compact](https://github.com/tmastalirsch/herdr-claude-safe-compact) | Idle-pane compact submission after a fresh note. | Disable blind fallback; verify completion; use current pane. |
| [Claude auto-compactor](https://github.com/EthanPany/claude-code-auto-compact) | Observes a new compaction marker rather than treating writes as success. | Reuse existing observation tooling without adding transcript paths to work state. |
| [Smart Ralph](https://github.com/tzachbon/smart-ralph) | Small state-aware Stop continuation pattern and approval gate. | Retain our skills, authority, sequential execution, and correction policy; no wholesale methodology adoption. |

Coordinate continuation and renewal so separate controllers cannot issue competing
commands. A minimal shared decision/check is preferable to installing independent
loops unchanged. Exact reuse versus small adaptation should follow source inspection
and testing, not an expanded architecture.

Primary platform contracts: [Claude skills](https://code.claude.com/docs/en/skills#inject-dynamic-context),
[Stop hooks](https://code.claude.com/docs/en/hooks#stop),
[Herdr automation](https://herdr.dev/docs/agent-automation/), and
[Herdr CLI](https://herdr.dev/docs/cli-reference/).

## Wire into repository sources, not generated configuration

| Source | Implementation seam |
| --- | --- |
| `agents/claude-code/settings.template.json` | Install native hooks/integration settings; coordinate with current `notify` Stop handler. |
| `agents/claude-code/setup-settings.sh` | Existing settings need an explicit update path; current script only creates absent files. |
| `agents/claude-code/default.nix` and setup shell | Package selected Claude-native skills/helpers and entry environment. |
| `agents/skills/mojo-*` | Authoritative policy sources; adapt executable initialization for Claude without writing a renderer. |
| `tools/setup-shared-shell.sh` | Verify actual skill installation/discovery in Claude-recognized locations. |
| `tools/agent-sandbox.sh` and `tools/setup-sandbox-paths.sh` | Verify allowed durable-store and Herdr socket access. |

Recheck current files before editing. Documentation records a target, not a tested
runtime. Preserve unrelated user work and use minimal edits.

## Implement in verifiable slices

1. Native entry and record: load selected skills, run initialization, resolve active
   work, and execute one bounded task under Mojo/style guidance.
2. Sequential ticket and review loop: fresh workers, isolated fixups, acceptance,
   verification, round recording, and final human stop.
3. Stop continuation: resume premature stops while preserving all human gates.
4. Renewal: reasoned handoff, current-pane compaction, confirmed completion, native
   resume entry, and intervention on failure.

These are implementation milestones, not a second set of tickets or a replacement
Dex outline. Publish actual implementation tickets through the selected Pocock flow.

## Required end-to-end checks

- Native executable initialization runs in the assigned checkout; language/role
  instructions arrive before editing without a custom renderer.
- A premature Stop resumes the recorded action without duplicate worker dispatch.
- A pending human gate remains stopped, including after context renewal.
- One ticket completes review/correction before the next starts.
- A rejected reviewer proposal leaves the active implementation unchanged; accepted
  proposals are verified and independently re-reviewed.
- The three-round count survives compaction and unresolved findings stop at the bound.
- Actual successful compaction is distinguished from terminal input acknowledgment.
- Handoff failure pauses for the user; no integration uses blind fallback.
- Current-pane handoff/compact/resume restores the interrupted permitted action.
- Agent completion stops at final human review, with Mojo-compliant retained history.

Choose exact thresholds and operational tuning from these checks. Do not expand
the continuation record to solve speculative failures before observing them.
