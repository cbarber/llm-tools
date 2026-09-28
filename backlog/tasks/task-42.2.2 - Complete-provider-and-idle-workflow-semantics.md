---
id: TASK-42.2.2
title: Complete provider and idle workflow semantics
status: To Do
assignee: []
created_date: '2026-09-28 21:44'
labels: []
dependencies: []
references:
  - agents/opencode/plugins/temper.ts
parent_task_id: TASK-42.2
priority: high
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make native provider tools and host-owned idle continuation obey the same serialized workflow event semantics as host-executed tools.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provider-executed tools deliver correlated before/after workflow facts and tool.finished exactly once.
- [ ] #2 Workflow activation occurs only at awaited explicit slash or skill-tool boundaries, never generic replayable part events.
- [ ] #3 Idle deadlines are persisted when scheduled, restored after restart, and invalidated by chat, busy, tool, stop, or replacement events.
<!-- AC:END -->
