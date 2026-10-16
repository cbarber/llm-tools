---
id: TASK-85
title: >-
  stop-continue nudges only the coordinating session and waits on all worker
  task types
status: To Do
assignee: []
created_date: '2026-10-16 18:24'
labels:
  - claude-code
  - follow-up
dependencies: []
references:
  - TASK-64
priority: low
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-64 review. The hook nudges every session in a checkout whose record says continue, including a non-coordinator session where the user is just chatting (up to 3 forced continuations per turn). Running background tasks of type workflow or teammate do not suppress the nudge; only subagent tasks do.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A session that is not coordinating the record is not nudged
- [ ] #2 Running workflow and teammate background tasks suppress the nudge like subagents
<!-- AC:END -->
