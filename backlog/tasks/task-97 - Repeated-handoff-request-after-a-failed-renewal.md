---
id: TASK-97
title: Repeated handoff request after a failed renewal
status: To Do
assignee: []
created_date: '2026-10-25 02:11'
labels:
  - follow-up
dependencies: []
references:
  - TASK-66
priority: medium
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66 final review. stop-continue reads the paused state only when stop_hook_active is true (stop-continue:119-135), so each later non-hook stop (a background wake) above the threshold asks for the handoff again instead of staying paused until the user acts.
<!-- SECTION:DESCRIPTION:END -->
