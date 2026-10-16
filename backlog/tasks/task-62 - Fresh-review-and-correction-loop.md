---
id: TASK-62
title: Fresh review and correction loop
status: Done
assignee: []
created_date: '2026-10-16 02:43'
updated_date: '2026-10-16 04:17'
labels:
  - workflow
dependencies:
  - TASK-61
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: high
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A reviewer entry built on the code-review skill reviews each ticket's commits, and finally the integrated result, in fresh context against the contract: ticket acceptance criteria, referenced approved design, and repository/Mojo standards, without the author's reasoning. Findings carry evidence and severity; spec gaps and Critical/Important findings block, Minor findings do not enter the loop (Jesse Vincent's rule). Reviewers may propose SHA-targeted fixups in an isolated worktree; the coordinator accepts or rejects, verifies accepted changes, and obtains fresh re-review. At most three correction rounds per scope, counted durably; unresolved blocking findings at the bound return to the user. Accepted fixups are folded into owning commits before the final stop.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A rejected proposal leaves the active implementation checkout unchanged
- [x] #2 Accepted proposals are verified and independently re-reviewed
- [x] #3 The round count survives context renewal and unresolved blocking findings stop at the third round
- [x] #4 Minor findings are reported without extending the correction loop
- [x] #5 Final retained history has accepted fixups folded into their owning commits
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-61 review: mojo-implement's Stop section sets complete=true directly; add the final integrated review step there, not only at the per-ticket seam (step 6).

From TASK-61 review: re-dispatching unfinished work on the same ticket must not reset correction_round or move the review base; the base is not stored in the record, so define how review scope survives context renewal (coordinate with TASK-65).

Review scope across renewal: each scope's report beside the work record starts with a `Base: <sha>` line (ticket reports at dispatch; the integrated scope uses the first approved ticket's base). The record links the report, never the base. Dispatch and final-review entry keep an existing base and correction_round, and mojo-implement initialization prints the scope, base, and round.
<!-- SECTION:NOTES:END -->
