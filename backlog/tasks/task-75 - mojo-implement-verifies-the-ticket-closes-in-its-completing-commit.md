---
id: TASK-75
title: mojo-implement verifies the ticket closes in its completing commit
status: To Do
assignee: []
created_date: '2026-10-16 04:08'
labels:
  - workflow
  - follow-up
dependencies: []
references:
  - TASK-61
priority: low
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-61 review. Reconciliation only checks that some commit in the range touched the ticket file, not that the Done transition sits in the commit completing the work; the brief also assumes backlog auto_commit is false.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Reconciliation flags a ticket closed in a separate bookkeeping commit
- [ ] #2 Behavior with backlog auto_commit enabled is handled or explicitly rejected
<!-- AC:END -->
