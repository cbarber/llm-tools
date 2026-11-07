---
id: TASK-83
title: Warn when a template hook cannot reach a locally deleted hook event
status: To Do
assignee: []
created_date: '2026-10-16 18:16'
labels:
  - claude-code
  - follow-up
dependencies: []
references:
  - TASK-63
priority: low
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-63 review. When a user deletes a whole hook event or group (e.g. Stop: [] to silence notify), a hook the template later adds there never arrives: local deletion wins on conflict. Someone who removed Stop to turn off notify will silently never get TASK-64's stop-continue hook. Deleting only the hook and leaving the empty group does let new hooks arrive.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Setup warns (once per template change) when a template hook addition is suppressed by a local deletion
- [ ] #2 Behaviour documented where the settings template is described
<!-- AC:END -->
