---
id: TASK-59
title: 'Claude-native initialization for mojo-init, mojo-commit, and mojo-pull-request'
status: Done
assignee: []
created_date: '2026-10-16 02:42'
updated_date: '2026-10-16 03:29'
labels:
  - workflow
dependencies: []
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: high
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Shared Mojo skills render their initialization context through Claude's native `!` executable-block syntax instead of the `{exec}` convention. Temper (both the bash CLI and the OpenCode plugin, which mirrors it) currently executes only `bash {exec}` blocks, so this ticket teaches both to execute `!` blocks, then converts the skills, keeping one syntax for both agents. Session initialization reports agent, sandbox, and Git state for the assigned checkout and loads active work; routine Forge status/next-action calls leave initialization and remain at actual PR steps. Blocked by: none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Invoking each of the three skills in Claude runs its initialization commands before the model reads the instructions, with output reflecting the assigned checkout
- [x] #2 The same skills still render their initialization under OpenCode via temper
- [x] #3 Session initialization no longer runs forge pr status or forge pr next-action
- [x] #4 Ordinary code examples in the skills are not executed
- [x] #5 Temper's CLI and OpenCode plugin execute `!` blocks with the same output and failure reporting they give `bash {exec}` blocks today
<!-- AC:END -->
