# Idea-to-PR workflow research

## Purpose

Reduce human interaction from roughly eight hours toward four; six is an
acceptable first improvement. Preserve intentional design, working atomic
commits, and final human code review. Matt Pocock and Dex Horthy are the
closest references. Poteto's stability checks are useful; hands-off decision
authority is not the desired default.

This collection records source rules and the decisions reached in the interview.
It does not yet specify an executable workflow.

## Read the collection

| Document | Purpose |
| --- | --- |
| [Patterns](workflow/patterns.md) | Small common statements, supporting authors, and disagreements |
| [Mojo policy](workflow/mojo.md) | Binding editing, history, review, and publication rules |
| [Session state](workflow/session-state.md) | Handoff requirements, current decisions, and storage questions |
| [Uncategorized](workflow/uncategorized.md) | Source statements awaiting classification or selection |
| [Matt Pocock](workflow/sources/matt-pocock.md) | Interview, spec, tickets, implementation, and context rules |
| [Dex Horthy](workflow/sources/dex-horthy.md) | Product/system/program design and vertical slices |
| [Review and stability sources](workflow/sources/review-stability.md) | Poteto, Addy Osmani, Jesse Vincent, and Harper Reed |

## Two paths, shared verification

**Bounded work:** the requested behavior is clear, the affected flow exists,
and code or an agreed design settles the consequential choices.

```text
ground the change → implement → verify → review/fix/re-verify → human review
```

**Design-bearing work:** implementation would otherwise choose consequential
behavior, ownership, contracts, or code shape without a settled precedent.

```text
ground the change → resolve decisions → choose verifiable slices
  → implement → verify → review/fix/re-verify → human review
```

These are the interview's organizing paths, not a claim that every author uses
the same stages. Product, system, and program design receive only the depth the
unresolved decisions need. A bounded change can still have wide operational impact.

Both paths need continuity between steps. The desired automation is sequential
handoff and ordinary implementation/review work, with humans retaining consequential
decisions. Pause frequency, decision authority, and verification depth are separate.

## Two costs in scope

| Cost | Question | Evidence |
| --- | --- | --- |
| System stability | What could break elsewhere, and what fact makes this change safe? | Trace real consumers; exercise the relevant behavior; mark unproven assumptions |
| Implementation/review | Is early clarification cheaper than reviewing and reworking the result? | Existing precedent, unresolved choices, implementation friction, review findings |

Sources qualify these costs but provide no calibrated threshold. File count,
line count, or agent confidence alone does not establish risk. Classification
can change when investigation or implementation exposes new facts; who approves
that change remains part of the authority policy to settle.

Long-term maintenance tracking is outside this collection. Experiment and
course-correct; a concrete concern can become a follow-up ticket linked to the
original work. No debt or maintenance-risk register is proposed.

## How to read the evidence

- A distilled statement is one independently comparable rule, not a merged skill.
- Source IDs lead to the actual instructions and their conditions. Local adaptations
  are distinguished from upstream text.
- Count distinct authors supporting the statement, not files or repeated wording.
  Frequency describes this selected corpus; it does not establish effectiveness.
- Keep human gates, scope exclusions, and contradictory authority policies visible.
- New statements start uncategorized if they do not fit. Add patterns only when
  the distinction proves useful.
- Published prompts establish what an author instructs. Biographies, anecdotes,
  and adoption are not workflow evaluations.

Research checked on 2026-10-06. Some upstream links track mutable `main` branches;
recheck those instructions before adopting them. [Mojo policy](workflow/mojo.md)
overrides conflicting external advice.
