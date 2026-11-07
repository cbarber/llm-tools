# Matt Pocock: source-backed workflow patterns

Checked **2026-10-06** against the [upstream README][readme], GitHub directory tree, actual upstream skill files, and installed files below. Upstream links are pinned to `6fd947921b935b7e1e69293a200400f0fdd5c15f`. These are independently attributable rules, not a recommended orchestration.

## Atomic rules

| Rule | Trigger or checkpoint | Source |
| --- | --- | --- |
| **M1. Ask only the decision frontier:** questions whose prerequisites are settled. | Each grilling round; dependent questions wait for later rounds. | Matt [grilling][grilling]; [local grilling][lg] |
| **M2. Look up facts; leave decisions to the user.** | A question needs environmental evidence. | Matt [grilling][grilling]; [local grilling][lg] |
| **M3. Require confirmed shared understanding before acting.** | Grilling frontier becomes empty. | Matt [grilling][grilling]; [local grilling][lg] |
| **M4. Capture resolved terminology immediately in a glossary.** | Domain terms become precise; challenge contradictions against code. | Matt [domain-modeling][domain]; [local adaptation][ld] |
| **M5. Offer an ADR only for a hard-to-reverse, surprising decision involving a real trade-off.** | All three conditions hold. | Matt [domain-modeling][domain]; [local domain-modeling][ld] |
| **M6. Synthesize the known conversation into a spec without another requirements interview.** | Spec creation; retain domain vocabulary and relevant ADRs. | Matt [to-spec][spec]; [local to-spec][ls] |
| **M7. Confirm testing seams with the user.** | Before spec publication; prefer existing, highest boundaries and fewer seams. | Matt [to-spec][spec]; [local to-spec][ls] |
| **M8. Make tickets complete vertical tracer bullets.** | Decomposition: narrow schema/API/UI/tests paths, independently demoable/verifiable, fitting one fresh context window. | Matt [to-tickets][tickets]; [local to-tickets][lt] |
| **M9. Approve granularity and genuine blocking edges before publishing tickets.** | Publish blockers first; work only tickets whose blockers are done. | Matt [to-tickets][tickets]; [local to-tickets][lt] |
| **M10. Use expand–contract for wide mechanical refactors.** | Prefer green migration batches; if impossible, upstream permits a shared integration branch with green promised at final integrate-and-verify. | Matt [to-tickets][tickets]; [local to-tickets][lt] |
| **M11. Test behavior through confirmed public seams, one failing test then minimal implementation per cycle.** | TDD implementation; avoid internal coupling and bulk test-first horizontal slicing. | Matt [tdd][tdd] |
| **M12. Reference existing artifacts rather than duplicating them in handoffs.** | Context transfer; tailor next-session focus, suggest skills, redact secrets. | Matt [handoff][handoff]; [local handoff][lh] |
| **M13. Keep every commit self-contained, buildable, and working.** | Binding local commit checkpoint; consolidate fix-of-fix chains into their owning commits. | Local [mojo-commit][mojo], not Matt |
| **M14. Execute the unblocked ticket frontier on one integration branch.** | `implement-spec`: implementers use ticket worktrees; merger agents integrate completed work and unblock more tickets. | Matt [implement-spec][implementation] |
| **M15. Communicate through context pointers.** | Spec, tickets, shared research outside the repo, and previous commits; avoid repeating their contents. | Matt [implement-spec][implementation] |
| **M16. Review the integrated result and dispatch one implementer to fix findings.** | All tickets complete; this text does not require an explicit re-review loop. | Matt [implement-spec][implementation] |
| **M17. Mark an existing draft ready after the implementation/review step.** | Upstream publication step; local human-review draft policy overrides automatic promotion here. | Matt [implement-spec][implementation] |

## Provenance and unresolved boundaries

Matt's [README][readme] presents small, adaptable, composable skills. Explicit upstream workflow links include [grill-with-docs][gwd] combining grilling/domain-modeling, and [implement-spec][implementation] consuming specs/tickets as a task graph on an integration branch. These descriptions do not prescribe adopting that orchestration here.

The complete implementation path is task graph → optional shared exploration →
ticket implementers/mergers → integrated review → one fix worker → tracker/PR
completion → worktree cleanup. Concurrency and automatic draft promotion are
source policies, not agreed requirements for this collection.

All five installed files were read. Similarity does **not** establish installation provenance, authorship of local edits, or an exact upstream version. Local `grilling` is upstream-like with formatting differences; local `domain-modeling` uses `CONTEXT.md`/`CONTEXT-MAP.md`, versus upstream `GLOSSARY.md`/`GLOSSARY-MAP.md`. Local spec, tickets, and handoff also contain wording/behavior differences.

M10's non-green integration exception conflicts with binding M13 if interpreted as permission for broken commits; it does not override mojo. Neither source supports “squash all”: mojo targets draft/fix chains while preserving distinct atomic purposes.

Both handoff sources require OS-temporary storage (upstream explicitly `$TMPDIR`, otherwise `/tmp`), outside the workspace. This conflicts with desired durable workflow state; retention and canonical storage remain **unresolved**.

[readme]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/README.md
[grilling]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/productivity/grilling/SKILL.md
[domain]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/domain-modeling/SKILL.md
[spec]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/to-spec/SKILL.md
[tickets]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/to-tickets/SKILL.md
[tdd]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/tdd/SKILL.md
[handoff]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/productivity/handoff/SKILL.md
[gwd]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/grill-with-docs/SKILL.md
[implementation]: https://github.com/mattpocock/skills/blob/6fd947921b935b7e1e69293a200400f0fdd5c15f/skills/engineering/implement-spec/SKILL.md
[lg]: /home/cbarber/.agents/skills/grilling/SKILL.md
[ld]: /home/cbarber/.agents/skills/domain-modeling/SKILL.md
[ls]: /home/cbarber/.agents/skills/to-spec/SKILL.md
[lt]: /home/cbarber/.agents/skills/to-tickets/SKILL.md
[lh]: /home/cbarber/.agents/skills/handoff/SKILL.md
[mojo]: ../../../agents/skills/mojo-commit/SKILL.md
