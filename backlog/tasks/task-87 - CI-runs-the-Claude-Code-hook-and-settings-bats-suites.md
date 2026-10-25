---
id: TASK-87
title: CI runs the Claude Code hook and settings bats suites
status: To Do
assignee: []
created_date: '2026-10-16 18:50'
labels:
  - claude-code
  - follow-up
dependencies: []
references:
  - TASK-65
priority: low
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-63/64/65 reviews. tools/claude-code-scripts/*.bats (stop-continue, compact-resume) and agents/claude-code/test-setup-settings.bats are not run by any CI workflow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A CI workflow runs the claude-code-scripts and setup-settings bats files when those paths change
<!-- AC:END -->
