---
id: TASK-64
title: Stop hook continuation
status: Done
assignee: []
created_date: '2026-10-16 02:43'
updated_date: '2026-10-16 18:21'
labels:
  - workflow
dependencies:
  - TASK-60
  - TASK-63
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: medium
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A Stop hook reads the current checkout's work record and, during approved execution with remaining work, blocks the stop with a reason directing Claude to continue from the recorded next action. Pending human gates and completed agent work are allowed to stop. Respects hook-continuation metadata, bounds repeated nudges without progress, never dispatches duplicate work while a worker is active, and coexists with the existing notify Stop handler. Does not inject skill bodies.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A premature stop during approved execution resumes the recorded action without duplicate worker dispatch
- [x] #2 A pending human gate (grilling, design approval, final review) remains stopped
- [x] #3 Repeated nudges without progress stop rather than loop
- [x] #4 A stop in one checkout never consults another checkout's record
- [x] #5 notify still fires
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-63: add the Stop hook inside the existing "" Stop group beside notify in settings.template.json. setup-settings.sh collapses same-matcher groups and keys hooks by command, so it reaches existing settings. It won't reach a checkout whose user deleted the whole Stop event/group (TASK-83).

stop-continue (tools/claude-code-scripts) runs beside notify in the "" Stop group. It allows the stop when a background agent task is running (the session wakes when it finishes), when there is no record, on wait-for-human/complete, and on an inconsistent record (with a systemMessage). Otherwise it blocks with the record's next_action. Progress means a changed record: at most 3 nudges per unchanged record within a chain of stop_hook_active continuations; a stop not caused by a hook resets the count. Nudge state lives in stop-nudges beside work.json, never in the record itself.
<!-- SECTION:NOTES:END -->
