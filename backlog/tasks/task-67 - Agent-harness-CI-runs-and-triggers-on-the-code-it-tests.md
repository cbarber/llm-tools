---
id: TASK-67
title: Agent harness CI runs and triggers on the code it tests
status: To Do
assignee: []
created_date: '2026-10-16 03:41'
labels:
  - workflow
  - follow-up
dependencies: []
references:
  - TASK-59
priority: low
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-59 review. The agent harness workflow's path filters still name the plugin's former location, so changes to the temper CLI, the OpenCode plugin, or shared skills alone do not trigger it; its run line also names a mojo-edit-nudge test file that no longer exists, which bun silently skips.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Changes to the temper CLI, the OpenCode temper plugin, or shared skills trigger the harness workflow
- [ ] #2 The workflow runs only test files that exist
<!-- AC:END -->
