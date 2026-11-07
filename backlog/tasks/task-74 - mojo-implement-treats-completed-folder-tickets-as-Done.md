---
id: TASK-74
title: mojo-implement treats completed-folder tickets as Done
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
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-61 review. Selection reads only backlog task list output, so a Done ticket moved by backlog task complete or cleanup shows as not found and the run can never reach all-Done; it stops at a human gate instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An approved ticket moved to the completed folder counts as Done for selection and completion
<!-- AC:END -->
