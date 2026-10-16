---
id: TASK-60
title: Per-checkout work records
status: Done
assignee: []
created_date: '2026-10-16 02:42'
updated_date: '2026-10-16 03:55'
labels:
  - workflow
dependencies: []
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: high
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A packaged helper creates, reads, and updates the small work record (current ticket and next action, pending human gate, correction-round count, branch, artifact links, agent/tool/session IDs) in a durable home-directory work folder, and exposes a continuation check returning continue, wait for human, or agent work complete. Each checkout/worktree resolves its own record so multiple working agents in different directories never share or clobber state. Workers return reports; only the coordinator writes its record. Blocked by: none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Two agents in different directories each resolve and update only their own record
- [x] #2 Writes are atomic: a concurrent reader never observes a partially written record
- [x] #3 A missing or inconsistent record is reported rather than inventing progress
- [x] #4 The continuation check distinguishes continue, pending human gate, and agent work complete
- [x] #5 The helper is available and can write its store from inside the agent sandbox
<!-- AC:END -->
