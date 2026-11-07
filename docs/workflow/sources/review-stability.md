# Review and stability: source rules

Checked **2026-10-06** against fetched primary texts (`main` is mutable). Harper's article: **2025-02-16**. Published instructions establish provenance, not evaluated reliability.

## Authors and scope

[Poteto][PB]: React Compiler engineer; [pstack][PI] cites Meta/Netflix/Cursor experience. [Addy Osmani][AB]: Claude Code at Anthropic, formerly Chrome developer-experience leadership at Google. [Jesse Vincent][JB]: Superpowers creator, Request Tracker/K-9 Mail creator, and former Perl 5 lead. [Harper Reed][HB]: former Threadless and Obama 2012 campaign CTO, now 2389.ai CEO. Biographies do not validate workflows.

User context: poteto's stability appeals; authority feels hands-off. Matt/[Dex](dex-horthy.md) remain human-review anchors, not source rules. No author is selected.

## Atomic rules


| ID | Minimum statement | Conditions / human gate | Source |
| --- | --- | --- | --- |
| P1 | Identify the load-bearing safety fact. | Blast-radius analysis; usually one or two facts. | [Blast][PBR] |
| P2 | Report attained proof level. | Assertion → source line → failure-path exclusion → real-code execution → running-app reproduction; advance cheaply. | [Blast][PBR] |
| P3 | Execute real code to prove that fact. | Paste outcome; label unavailable proof unproven. | [Blast][PBR] |
| P4 | Trace dependencies beyond symbol callers. | Pinned libraries, timing, wire formats, downstream consumers. | [Blast][PBR] |
| P6 | Verify the actual task artifact. | Before declaring done; compilation and self-report are proxies. | [Proof][PP] |
| P8 | Compare structurally distinct designs. | Architect requires at least two before synthesis. | [Architect][PA] |
| P9 | Proceed after design synthesis. | Sign-off only when requested. | [Architect][PA] |
| P11 | Use diverse read-only reviewers. | Interrogate; clarify uncertain intent with user first. | [Interrogate][PR] |
| P12 | Adjudicate reviewer findings. | Lead assigns act-on/consider/noted/dismissed; preserve disagreements. | [Interrogate][PR] |
| P13 | Return a verdict without automatically applying changes. | Interrogate alone prescribes no fix/re-review loop. | [Interrogate][PR] |
| P14 | Execute reversible work without permission pauses. | Human owns product direction; irreversible actions require confirmation. | [Autonomy][PN] |
| A1 | Cross-examine non-trivial artifacts with fresh context. | Doubt skill scope; mechanical work excluded; TDD RED can satisfy behavioral doubt. | [Doubt][AD] |
| A2 | Send artifact and contract without author reasoning. | Adversarial reviewer; decompose oversized artifacts. | [Doubt][AD] |
| A3 | Reconcile findings against artifact text. | Orchestrator retains judgment; repair unclear contracts first. | [Doubt][AD] |
| A4 | Fix actionable findings and re-loop. | Document accepted trade-offs separately. | [Doubt][AD] |
| A5 | Bound doubt to three cycles. | Earlier exit for trivial/repeated findings or user override; unresolved third cycle escalates. | [Doubt][AD] |
| A6 | Offer cross-model review every interactive cycle. | External CLI requires explicit authorization per invocation; announce non-interactive skip. | [Doubt][AD] |
| A7 | Stop after the next task by default. | `/build`; cadence, not independent reviewer authority. | [Build][AC] |
| A8 | Execute an approved full plan continuously. | `/build auto`; one initial approval preserves per-task verification. | [Build][AC] |
| A9 | Stop for unresolved specification decisions. | Auto mode also gates high-risk/irreversible work and failures without obvious fixes. | [Build][AC] |
| J1 | Obtain path-specific approval before implementation. | Spike probe, bounded chat design, or architectural written spec and plan/execution choice. | [Brainstorm][JBS] |
| J2 | Require task spec and quality verdicts. | Independent task reviewer; self-review cannot substitute. | [SDD][JS] |
| J3 | Inspect outside the diff only for named risks. | Task review; focused checks, no broad crawl. | [Reviewer][JT] |
| J4 | Fix blocking task findings. | Spec gaps or Critical/Important findings; Minor findings bypass loop. | [SDD][JS] |
| J5 | Re-review each fix. | Existing findings plus new breakage in fix diff; untouched-code observations cannot extend loop. | [Re-review][JR] |
| J6 | Cap task fixes at five rounds. | Escalate implementer capability in rounds four/five; controller adjudicates residuals at cap. | [SDD][JS] |
| J7 | Perform one broad final review. | Findings receive one fix wave and scoped re-review, then adjudication. | [SDD][JS] |
| J8 | Continue approved execution through ordinary ambiguity. | Controller rulings; stop for irreversible, security-sensitive, external side effects, or wholly speculative paths. | [SDD][JS] |
| H1 | Run code/tests before advancing prompts. | Personal 2025 practice; failures return to debugging, no mandatory independent reviewer. | [Workflow][HW] |

## Contradictions and adjacent policies

Mandatory review/fix/re-review is common to Addy's doubt scope and Jesse's task loop, not all authors. Poteto separates verdict from remediation. Runtime proof exceeds dependency graphs; architectural uncertainty is distinct from operational impact.

Authority: P9/P14 favor asynchronous supervision; J1 gates design, J8 delegates execution rulings; A9 returns unresolved decisions to humans. A7/A8 alter cadence, not A9 authority. Bounds: Addy's three cycles escalate; Jesse's five rounds/single final wave permit adjudication. Internal tension: Jesse's reviewer says humans decide plan-mandated defects; SDD assigns controller rulings.

Adjacent/out-of-scope: pstack code-as-spec, delegation, PR/model policies; Addy TDD/commits; Jesse worktrees/session ledger/cleanup; Harper planning/context bundling. No long-term maintenance tracking is inferred.

[PB]: https://github.com/poteto
[PI]: https://github.com/cursor/plugins/blob/main/pstack/README.md
[AB]: https://addyosmani.com/bio/
[JB]: https://blog.fsck.com/about/
[HB]: https://www.harperreed.com/
[PBR]: https://github.com/cursor/plugins/blob/main/pstack/skills/blast-radius/SKILL.md
[PP]: https://github.com/cursor/plugins/blob/main/pstack/skills/principle-prove-it-works/SKILL.md
[PA]: https://github.com/cursor/plugins/blob/main/pstack/skills/architect/SKILL.md
[PR]: https://github.com/cursor/plugins/blob/main/pstack/skills/interrogate/SKILL.md
[PN]: https://github.com/cursor/plugins/blob/main/pstack/skills/principle-never-block-on-the-human/SKILL.md
[AD]: https://github.com/addyosmani/agent-skills/blob/main/skills/doubt-driven-development/SKILL.md
[AC]: https://github.com/addyosmani/agent-skills/blob/main/.claude/commands/build.md
[JBS]: https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md
[JS]: https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md
[JT]: https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/task-reviewer-prompt.md
[JR]: https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/re-review-prompt.md
[HW]: https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/
