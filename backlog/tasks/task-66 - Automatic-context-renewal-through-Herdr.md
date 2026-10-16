---
id: TASK-66
title: Automatic context renewal through Herdr
status: To Do
assignee: []
created_date: '2026-10-16 02:43'
labels:
  - workflow
dependencies:
  - TASK-64
  - TASK-65
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: medium
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When context renewal is needed, request a reasoned handoff, confirm readiness, let the turn settle, submit /compact to the current pane through Herdr, confirm that compaction actually occurred (not merely that input was delivered), then submit the resume entry. Any failure preserves work and pauses for the user; no blind or emergency fallback, background session, or same-pane clear. Continuation and renewal share one decision so separate controllers never issue competing commands. Includes source inspection of the candidate integrations (context meter, compact handoff, safe compact, auto-compactor) and sandbox access to the Herdr socket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Successful compaction is distinguished from terminal input acknowledgment
- [ ] #2 Handoff or compaction failure pauses for the user
- [ ] #3 Current-pane handoff, compact, and resume restores the interrupted permitted action
- [ ] #4 Stop continuation and renewal never issue competing commands
<!-- AC:END -->
