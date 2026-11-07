---
id: TASK-73
title: mojo-implement reports missing and unapproved current tickets accurately
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
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-61 review. Initialization reports any current_ticket that is not an open approved ticket as 'closed but not yet reconciled', including tickets that do not exist or are outside the approved set.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A missing current ticket and an unapproved current ticket are each reported as such
<!-- AC:END -->
