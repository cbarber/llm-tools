# Claude workflow architecture

Status: selected architecture for implementation, with runtime integration still
to be validated. [Decisions](decisions.md) define the choices and boundaries;
[program design](program-design.md) maps them to concrete pieces.

## Engineering skills own the flow

The main interactive conversation coordinates the work. It uses selected skills
to resolve decisions, dispatch implementation and review, reconcile results, and
record progress. Applicable instructions are loaded at entry, not injected at
every edit or tool event.

```text
current interactive Claude conversation
  ├─ design: Pocock question frontier + Dex product/system/program guidance
  ├─ decomposition: Pocock spec + dependency-linked tickets
  ├─ implementation: sequential ticket execution + Mojo discipline
  ├─ review: fresh artifact/contract review + fixup proposals
  └─ progress: small work.json + references to existing artifacts

continuation hook
  └─ nudge approved unfinished work; allow intentional human stops

Herdr renewal transport
  └─ reasoned handoff → compact current pane → confirm → resume entry
```

This is not an independent scheduler choosing product or engineering direction.
The hook keeps the instructed agent moving from recorded progress. Herdr provides
terminal control and observation, not task-completion or human-approval authority.

## Bounded work avoids unnecessary front-loading

Use this path when requested behavior is clear and code or an existing agreement
settles consequential choices:

```text
ground change
  → main-conversation implementation
  → verification
  → fresh review / correction
  → final human review
```

Poteto's safety-fact approach can inform proof of a bounded change. If grounding
or implementation exposes an unresolved consequential decision, obtain the needed
human decision rather than silently choosing it. A full document sequence is not
required for a change whose decisions are already settled.

## Design-bearing work resolves choices before ticket execution

```text
ground problem and codebase
  → Pocock-style grilling with Dex product-first guidance
  → review product solution
  → system/architecture discussion and human approval
  → program-design discussion and human approval
     including testing seams where practical
  → Pocock spec synthesis
  → Pocock vertical tickets and blocking relationships
  → human approval of ticket breakdown
  → sequential implementation / verification / review / correction
  → final integrated review / correction
  → final human review
```

Design depth follows unresolved decisions. Use selective contracts, signatures,
call trees, and responsibility views to make those decisions reviewable.
Specifications and tickets reference the agreed design instead of reproducing it.
Do not create a second decomposition in a Dex structure outline.

Implementation can reveal new facts. Update the coherent design and obtain focused
human re-review before overriding an agreed decision. Preserve unaffected approvals.

## One ticket reaches a reviewed result before the next begins

```text
coordinator selects next unblocked ticket
  → fresh implementer reads task/design and front-loaded Mojo/style guidance
  → implementation report, commits, and verification evidence
  → fresh reviewer reads artifact + agreed contract
  → findings and optional isolated fixup proposals
  → coordinator accepts/rejects proposals
  → verify accepted result
  → fresh re-review
  → complete ticket, repeat correction, or pause for human
```

The same review/correction mechanism applies to the integrated result. Three
correction rounds after initial review bound both loops. Final agent review does
not substitute for the human's intentional review or stamp.

## Existing artifacts carry engineering context

| Artifact | Responsibility |
| --- | --- |
| Product/design documents | Agreed behavior, consequential decisions, rationale, open details, and approved revisions. |
| Spec | Synthesis of the implementation contract and testing decisions. |
| Tickets | Independently verifiable slices, acceptance criteria, and dependencies. |
| Implementation/review reports | Findings, proposals, actual checks, and evidence. |
| Git branches and commits | Actual implementation and proposed corrections under Mojo history rules. |
| Handoff | Reasoned current-work summary with references and next action. |
| `work.json` | Operational cursor, human gate, correction round, branch, artifact links, and agent/tool/session IDs. |

Keep content in its owning artifact. The small record links to it; it is not a
transcript, second spec, or comprehensive recovery database. The coordinator
reconciles reported outcomes with actual artifacts and Git before advancing.

## Context renewal preserves work and human gates

```text
context renewal needed
  → request reasoned handoff
  → confirm handoff readiness, or pause for human on failure
  → wait for eligible settled terminal
  → submit /compact to current Herdr pane
  → confirm compaction
  → invoke resume entry to reload skills and work references
  → reconcile and continue only permitted work
```

Compaction is the initial choice, not an irrevocable architecture constraint.
Conversation boundaries need not coincide with design stages or ticket boundaries.
A renewed context does not reopen approved decisions or clear a pending human gate.

Native auto-compaction interaction and failure handling must be tested so the
chosen intervention policy has a chance to run before exhaustion. A mechanical
PreCompact checkpoint may supply evidence, but does not replace the required
reasoned handoff or authorize blind fallback.

## Intentional stops remain intentional

Pause for consequential unresolved decisions, overrides of approved decisions,
unresolved findings at the correction limit, handoff failure, and final human
review. Grilling is interactive; automation does not answer its questions.

Premature stops during approved execution are different: a worker may have returned
but review remains, proposals may await reconciliation, another approved ticket
may be ready, or renewed context may need pickup. These are the continuation
hook's purpose. Herdr's terminal `done` state alone does not establish work completion.

## Source behavior and local adaptations remain distinguishable

Pocock supplies the spec/ticket implementation backbone, but concurrency, mandatory
TDD, final-only agent review, and automatic draft promotion are adapted. Dex supplies
design views and approvals, but its separate outline and default per-phase human
pauses are not retained. Addy supplies fresh review and reconciliation; reviewer
fixups and the selected correction-round counting are local choices.

Refer to [source research](../workflow.md#read-the-collection) and
[program integration candidates](program-design.md#reuse-existing-integration-mechanisms)
for evidence. Recheck mutable upstream sources before adapting them.
