---
id: TASK-71
title: work-record documents and distinguishes stale-lock timeouts
status: To Do
assignee: []
created_date: '2026-10-16 03:52'
labels:
  - workflow
  - follow-up
dependencies: []
references:
  - TASK-60
priority: low
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-60 review. A lock left by a SIGKILLed writer makes later writers time out and exit 1, an exit code the help text does not list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lock timeout uses a documented exit code
<!-- AC:END -->
