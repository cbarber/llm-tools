---
id: TASK-119
title: Skill install reports a failed copy
status: To Do
assignee: []
created_date: '2026-11-01 02:28'
labels:
  - follow-up
dependencies: []
references:
  - TASK-102
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-102 review. tools/setup-shared-shell.sh syncs skills with rsync ... 2>/dev/null || true, and some installed skill dirs are read-only, so a failed copy is silent and an installed skill can stay stale (e.g. mojo-complete without its hide flags). Report the failure. Related: TASK-111 (same script, pruning).
<!-- SECTION:DESCRIPTION:END -->
