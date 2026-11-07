---
id: TASK-63
title: Settings template changes reach existing sessions
status: Done
assignee: []
created_date: '2026-10-16 02:43'
updated_date: '2026-10-16 04:30'
labels:
  - workflow
dependencies: []
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: medium
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Shell setup merges hook and setting changes from the Claude Code settings template into an existing generated local settings file, instead of only creating the file when absent, while preserving local edits. Prefactor for the Stop continuation hook. Blocked by: none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A new template hook appears in an existing generated settings file after re-entering the shell
- [x] #2 Local edits to the generated settings survive the merge
- [x] #3 Re-entering the shell repeatedly is idempotent
<!-- AC:END -->
