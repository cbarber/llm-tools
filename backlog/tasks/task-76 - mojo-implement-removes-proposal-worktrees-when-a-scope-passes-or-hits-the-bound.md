---
id: TASK-76
title: >-
  mojo-implement removes proposal worktrees when a scope passes or hits the
  bound
status: To Do
assignee: []
created_date: '2026-10-16 04:28'
labels:
  - workflow
  - follow-up
dependencies: []
references:
  - TASK-62
priority: low
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-62 review. Proposal worktrees and review branches are removed only inside a correction round, so they stay registered when a scope passes or reaches the three-round human gate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No review worktree or branch remains after a scope passes or reaches the bound
<!-- AC:END -->
