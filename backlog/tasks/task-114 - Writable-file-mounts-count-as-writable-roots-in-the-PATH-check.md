---
id: TASK-114
title: Writable file mounts count as writable roots in the PATH check
status: To Do
assignee: []
created_date: '2026-11-01 02:28'
labels:
  - follow-up
dependencies: []
references:
  - TASK-89
ordinal: 113000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-89 review (unproven). Writable file mounts such as ~/.claude.json and SANDBOX_EXTRA_RW files are not in _writable_roots, so a PATH entry resolving through them is not refused. Confirm and include them.
<!-- SECTION:DESCRIPTION:END -->
