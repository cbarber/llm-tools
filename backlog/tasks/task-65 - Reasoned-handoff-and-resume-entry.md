---
id: TASK-65
title: Reasoned handoff and resume entry
status: In Progress
assignee: []
created_date: '2026-10-16 02:43'
updated_date: '2026-10-16 18:30'
labels:
  - workflow
dependencies:
  - TASK-60
  - TASK-61
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: medium
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The coordinator writes a reasoned handoff tied to the current work and links it from the work record. After compaction of the current pane, a native resume entry reloads applicable skills, the work record, and handoff references, reconciles progress against Git, and continues only permitted work. Renewal does not reopen approvals or clear a pending human gate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After a manual /compact, the resume entry restores the interrupted permitted action
- [x] #2 A pending human gate remains pending after resume
- [x] #3 A missing or stale handoff for the current work pauses for the user
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC1 needs a live manual /compact in Claude Code: the SessionStart compact hook output and the mojo-resume rendering are verified by simulation (bats, bun), but delivery of additionalContext after a real /compact and the agent restoring the interrupted action have not been observed.
<!-- SECTION:NOTES:END -->
