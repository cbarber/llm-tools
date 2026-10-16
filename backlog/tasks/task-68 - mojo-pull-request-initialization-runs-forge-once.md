---
id: TASK-68
title: mojo-pull-request initialization runs forge once
status: To Do
assignee: []
created_date: '2026-10-16 03:41'
labels:
  - workflow
  - follow-up
dependencies: []
references:
  - TASK-59
priority: low
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-59 review. The mojo-pull-request initialization block echoes a label containing backtick command substitution, so forge pr status runs twice per skill load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Loading mojo-pull-request runs forge pr status exactly once and still shows its output
<!-- AC:END -->
