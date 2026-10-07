# Dex Horthy / HumanLayer

Date checked: **2026-10-06**; `main` links are mutable. This is a source aggregation, not a prescribed workflow harness. The table distills fetched public instructions and identifies prose recommendations separately.

## Provenance and evidence

Dex Horthy leads HumanLayer; [WSFF] explicitly discloses his commercial interest in human/agent collaboration tools. His experience motivates useful practices, but anecdotes, estimated task distributions, and claimed speedups are not controlled evidence. He acknowledges that the cited incident report is correlational and that his maintainability claim is unproven. Skill text establishes published instructions, not demonstrated reliability or enforced behavior.

The first-party [OpenCode integration][Integration] is explicitly alpha and distributes HumanLayer skills copied from its pi extension. Its README describes a published build sourced from `humanlayer/synclayer`. The current [Reference] is hand-written product documentation; command aliases and auto-advance descriptions should not be mistaken for identical behavior in every integration. [WSFF] is author prose. The historical `humanlayer/humanlayer` [Claude command][Historical] uses `thoughts/shared/plans/`, whereas these skills use `.humanlayer/tasks/`; it is lineage, not the current specification.

“Dex” here means Dex Horthy, not the unrelated Bryson CLI. A user-maintained fork is third-party, even when it derives from HumanLayer; this aggregation attributes rules to the linked first-party sources.

## Atomic rules

| ID | Statement | Trigger / checkpoint | Source |
| --- | --- | --- | --- |
| D1 | The human selects the shortest workflow providing needed review points. | Task creation: Oneshot, RPI, PRD-Oriented, or Freeform. | [Guide] |
| D2 | Invoke each of the six skills only when explicitly named by the user. | Skill selection. | [PRD], [TDD], [Discussion], [Outline], [Implement], [Iterate] |
| D3 | Define product WHAT and WHY; defer implementation questions to technical design. | PRD interview. | [PRD] |
| D4 | Settle the problem and success measure before interviewing the solution. | PRD foundation. | [PRD] |
| D5 | Ask exactly one decision question per message. | PRD and TDD interviews. | [PRD], [TDD] |
| D6 | Patch the document only after the decision is resolved. | Interview feedback or clarification. | [PRD], [TDD] |
| D7 | Obtain human approval of the complete product solution. | PRD completion. | [PRD] |
| D8 | Obtain System Design sign-off before opening Program Design. | Cross-component architecture review. | [TDD] |
| D9 | Obtain separate human approval of Program Design. | Code-shape review. | [TDD] |
| D10 | Keep design-discussion questions open until the user clearly decides. | Initial discussion and subsequent feedback. | [Discussion] |
| D11 | Use selective visual views: mockups, contracts, call/component trees, file diffs, signatures, or pseudocode. | Product, architecture, and code-shape decisions. | [PRD], [TDD] |
| D12 | Keep documents concise and coherent; rewrite sections instead of accumulating a decision log. | Recording settled choices. | [TDD] |
| D13 | Prefer thin vertical phases independently verifiable without a later phase. | Structure outline creation. | [Outline] |
| D14 | Outline feedback updates the outline rather than starting implementation. | Planning corrections. | [Outline] |
| D15 | Normally implement and automatically verify one phase, then wait for human review before committing or continuing. | Phase completion; explicit multi-phase requests alter pause timing. | [Implement] |
| D16 | Send 1–3 slices at a time and review the actual code while progressing. | Author's usual implementation practice, not a fixed skill limit. | [WSFF] |
| D17 | Verify feedback against artifacts, diff, and commits; apply understood fixes and run tests/lint. | Follow-on implementation feedback. | [Iterate] |
| D18 | Expose externally stored task artifacts through a repository-visible task link. | OpenCode integration: `.humanlayer/tasks/<slug>` links into `~/.humanlayer/riptide/artifacts/`. | [Integration] |
| D19 | Attach a new session to an existing task explicitly or through an unambiguous worktree link. | Explicit attach takes priority over environment selection and worktree discovery; fallback creates a task. | [Integration] |

## Limits of the aggregation

Depth selection is human judgment; these sources establish no proven automated risk classifier. Current documentation permits supported auto-advance but retains human design handoffs. Human feedback and implementation iteration are documented; an independent reviewer-agent/fixup loop is not established by these public sources. Automated checks and human code review have distinct roles.

[Guide]: https://docs.humanlayer.com/guide/skills-workflows
[Reference]: https://docs.humanlayer.com/reference/skills-workflows
[Integration]: https://github.com/humanlayer/humanlayer-opencode/blob/main/README.md
[PRD]: https://github.com/humanlayer/humanlayer-opencode/blob/main/skills/create-prd/SKILL.md
[TDD]: https://github.com/humanlayer/humanlayer-opencode/blob/main/skills/create-tech-design/SKILL.md
[Discussion]: https://github.com/humanlayer/humanlayer-opencode/blob/main/skills/create-design-discussion/SKILL.md
[Outline]: https://github.com/humanlayer/humanlayer-opencode/blob/main/skills/create-structure-outline/SKILL.md
[Implement]: https://github.com/humanlayer/humanlayer-opencode/blob/main/skills/implement-outline/SKILL.md
[Iterate]: https://github.com/humanlayer/humanlayer-opencode/blob/main/skills/iterate-implementation/SKILL.md
[WSFF]: https://github.com/humanlayer/advanced-context-engineering-for-coding-agents/blob/main/wsff.md
[Historical]: https://github.com/humanlayer/humanlayer/blob/main/.claude/commands/implement_plan.md
