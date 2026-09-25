---
id: TASK-13
title: Design git hooks for workflow enforcement
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-09-24 03:47'
labels:
  - task
dependencies: []
priority: medium
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Shell functions vs git hooks. Check existing hooks (beads), worktree compatibility, sandbox .git resolution
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Research conclusion (2026-09-23): use one workflow broker with typed OpenCode tools and Nix PATH wrappers as initial adapters; keep tool.execute.before parsing as conservative preflight only. Bash DEBUG/preexec is too bypassable. Fence v0.1.62 runtimeExecPolicy=argv is available in this Linux sandbox and is the preferred coarse runtime hardening layer, but it is not a state machine or complete event source. Strong future enforcement should move Git metadata and forge credentials behind an external broker, with repository locking, postcondition checks, normalized before/success/failure events, and server-side rulesets for remote invariants.
<!-- SECTION:NOTES:END -->
