---
id: TASK-64
title: Stop hook continuation
status: To Do
assignee: []
created_date: '2026-10-16 02:43'
updated_date: '2026-10-16 18:16'
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
- [ ] #1 A premature stop during approved execution resumes the recorded action without duplicate worker dispatch
- [ ] #2 A pending human gate (grilling, design approval, final review) remains stopped
- [ ] #3 Repeated nudges without progress stop rather than loop
- [ ] #4 A stop in one checkout never consults another checkout's record
- [ ] #5 notify still fires
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-63: add the Stop hook inside the existing "" Stop group beside notify in settings.template.json. setup-settings.sh collapses same-matcher groups and keys hooks by command, so it reaches existing settings. It won't reach a checkout whose user deleted the whole Stop event/group (TASK-83).
<!-- SECTION:NOTES:END -->
