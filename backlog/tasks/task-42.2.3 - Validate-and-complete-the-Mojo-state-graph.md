---
id: TASK-42.2.3
title: Validate and complete the Mojo state graph
status: In Progress
assignee: []
created_date: '2026-09-28 21:44'
updated_date: '2026-09-29 18:43'
labels: []
dependencies: []
references:
  - agents/skills/mojo-init/workflow.ts
  - agents/opencode/plugins/temper.ts
parent_task_id: TASK-42.2
priority: medium
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finish machine validation and the review/approval/merge behavior required by the real Mojo workflow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Bounded xstate/graph validation rejects dead ends, unsupported invokes/spawns/delays, and invalid representative transitions before activation.
- [ ] #2 The Mojo machine handles publication, approval, review feedback, head updates, and merge completion.
- [ ] #3 Malformed persisted XState internals are rejected before createActor restoration.
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-29 18:43
---
Mojo has author/team waiting and review-response transitions plus merge cleanup, and the runtime rejects basic malformed persisted snapshots and unreachable/dead-end/delayed states. xstate/graph traversal, unsupported spawn/invoke cases, and representative review/merge paths remain.
---
<!-- COMMENTS:END -->
