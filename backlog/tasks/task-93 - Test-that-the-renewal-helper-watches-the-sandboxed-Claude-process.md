---
id: TASK-93
title: Test that the renewal helper watches the sandboxed Claude process
status: To Do
assignee: []
created_date: '2026-10-25 01:21'
labels:
  - follow-up
  - claude-code
dependencies: []
references:
  - TASK-66
priority: low
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66 exec-fix review. Nothing checks that the --watch PID passed by sandboxed-claude is the PID of the exec'd sandbox script; dropping exec or moving start-renewal-helper out of the subshell would make the helper watch the wrong process.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 test-setup-shell.bats asserts the --watch PID equals the sandbox script's PID
<!-- AC:END -->
