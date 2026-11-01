---
id: TASK-102
title: Claude agents cannot discover mojo-complete; OpenCode keeps it
status: To Do
assignee: []
created_date: '2026-10-28 02:39'
updated_date: '2026-11-01 02:22'
labels:
  - follow-up
  - skills
dependencies: []
references:
  - TASK-99
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
mojo-complete pushes, force-pushes and pulls with rebase, which contradicts coordinator-only publishing. Its jobs in Claude now belong to the Stop hook, mojo-implement, mojo-review and mojo-handoff. OpenCode still triggers it through temper on session idle. Decision (human, 2026-10-31): the simplest fix that keeps OpenCode working is to make mojo-complete undiscoverable to Claude agents.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Claude Code sessions do not list or auto-invoke mojo-complete
- [ ] #2 OpenCode's temper idle trigger still runs mojo-complete
- [ ] #3 A test or documented check shows both
<!-- AC:END -->
