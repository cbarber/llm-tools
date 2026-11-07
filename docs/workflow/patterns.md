# Common-rule ledger

The five groups organize the current evidence. Statements are the smallest
useful shared rules; the source documents retain conditions and exceptions.
Counts are distinct supporting authors in this collection, not votes to adopt.
Binding local policy is recorded separately and never outvoted.

Source keys: [M: Matt](sources/matt-pocock.md),
[D: Dex](sources/dex-horthy.md),
[P: poteto, A: Addy, J: Jesse, H: Harper](sources/review-stability.md).

## 1. Ground the change

| ID | Distilled statement | Support | Authors |
| --- | --- | --- | --- |
| G1 | Investigate factual questions before asking the human to decide. | M2; Dex TDD context/research instructions | Matt, Dex (2) |
| G2 | Check implementation feedback against the actual code and artifacts. | D17, A3, P12 | Dex, Addy, poteto (3) |

Grounding supplies facts, not permission. Dependency graphs can locate consumers;
they cannot establish runtime safety or complete dependency coverage.

## 2. Resolve consequential choices

| ID | Distilled statement | Support | Authors |
| --- | --- | --- | --- |
| C1 | Obtain human agreement on the required design before implementation. | M3, D7–D9, J1 | Matt, Dex, Jesse (3) |
| C2 | Show consequential code shape before filling in implementation. | D11; poteto architect sketch instructions | Dex, poteto (2) |
| C3 | Record resolved choices in a coherent artifact. | M4–M6, D6/D12 | Matt, Dex (2) |

**Differences:** Matt asks the available decision frontier; Dex asks one decision
per message. Jesse requires approval even for bounded designs. Poteto's architecture
approval is opt-in. C1 therefore is not universal. C3 does not require the same
artifact: glossary, ADR, spec, and technical design have different purposes.

## 3. Choose verifiable slices

| ID | Distilled statement | Support | Authors |
| --- | --- | --- | --- |
| S1 | Divide work into thin, independently verifiable vertical slices. | M8, D13 | Matt, Dex (2) |
| S2 | Make genuine dependencies explicit and execute only the unblocked frontier. | M9/M14 | Matt (1) |
| S3 | Verify the current unit before advancing. | D15, A7/A8, H1 | Dex, Addy, Harper (3) |

**Differences:** a ticket, phase, prompt, and commit are not interchangeable units.
Dex commonly reviews one to three slices; Addy's build modes change task cadence;
Harper's described workflow advances only when the current result works. None determines authority solely
through cadence. [Mojo](mojo.md) requires every retained commit to be a working,
self-contained stopping point; non-green integration exceptions do not apply.

## 4. Verify behavior and impact

| ID | Distilled statement | Support | Authors |
| --- | --- | --- | --- |
| V1 | Exercise behavior through real interfaces rather than implementation proxies. | M11, P3/P6 | Matt, poteto (2) |
| V2 | Identify and prove the fact on which operational safety depends. | P1–P3 | poteto (1) |
| V3 | Trace dependencies beyond direct symbol callers. | P4 | poteto (1) |

Poteto's proof ladder: assertion → source reference → failure-path exclusion →
real-code execution → running-system reproduction. Report the attained level;
mark missing proof unproven. Compilation, a graph, and a reassuring summary
answer different questions from a behavioral check.

## 5. Review, correct, and re-verify

| ID | Distilled statement | Support | Authors |
| --- | --- | --- | --- |
| R1 | Give an independent reviewer the artifact and the criteria it must satisfy. | A2, J2; P11 uses read-only reviewers | Addy, Jesse, poteto (3) |
| R2 | Evaluate findings rather than treating the reviewer as authoritative. | A3, P12, J6 | Addy, poteto, Jesse (3) |
| R3 | Correct defects identified by the review/feedback step. | M16, A4, J4/J5, D17 | Matt, Addy, Jesse, Dex (4) |
| R4 | Re-review fixes in a bounded loop. | A4/A5, J5/J6 | Addy, Jesse (2) |

R3 does not imply independent re-review or the same verification contract in every source. Poteto's interrogation
returns a verdict without applying fixes. Dex's public iteration skill consumes
feedback but does not establish a dedicated independent-review loop. Matt's
implementation skills call code review; `implement-spec` dispatches one fix worker,
but neither establishes a repeated independent re-review loop.

**Differences:** Addy escalates unresolved doubt after three cycles. Jesse permits
five task-fix rounds, then controller adjudication; final review has one fix wave.
These bounds and residual-defect policies are not a common rule. Reviewer-proposed
patches/fixup commits are the user's preferred direction, not a verified Horthy rule.

## Cross-cutting continuity

M12/M15 make handoffs reference artifacts instead of copying them. Fresh contexts
need the current contract, relevant evidence, unresolved questions, and next action.
Durable shared state is an interview requirement; its storage and gate protocol
remain [unresolved](session-state.md). Other unmerged rules remain
[uncategorized](uncategorized.md).
