---
id: TASK-103
title: mojo-review checks the trailer only on agent commits
status: To Do
assignee: []
created_date: '2026-10-28 02:39'
labels:
  - follow-up
dependencies: []
references:
  - TASK-99
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-99 review. mojo-review's Standards axis flags any commit without Authored-By, so human commits in an integrated range would be reported. It should require the trailer on every agent commit, and the reconcile push check should state that it needs a non-empty range and that empty output passes.
<!-- SECTION:DESCRIPTION:END -->
