---
id: TASK-42.2.1
title: Harden Temper workflow effects and persistence
status: To Do
assignee: []
created_date: '2026-09-28 21:44'
labels: []
dependencies: []
references:
  - agents/opencode/plugins/temper.ts
  - agents/opencode/plugins/workflow-runtime.ts
parent_task_id: TASK-42.2
priority: high
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fix review-blocking security and lifecycle defects in the OpenCode workflow runtime.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Render each skill's bash {exec} blocks exactly once, treating command output as data.
- [ ] #2 Redact commands, outputs, errors, and event metadata before writing JSONL traces.
- [ ] #3 Validate restored workflow sources against app.skills({ directory }) and discard malformed or incompatible envelopes.
- [ ] #4 Stopping or replacing a workflow prevents all queued operations from persisting or delivering effects.
<!-- AC:END -->
