---
id: TASK-84
title: stop-continue reports when it cannot consult the work record
status: To Do
assignee: []
created_date: '2026-10-16 18:24'
labels:
  - claude-code
  - follow-up
dependencies: []
references:
  - TASK-64
priority: low
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-64 review. A missing work-record (or any unexpected exit) falls into allow_stop silently, so the hook is disabled without notice; the nix wrapper relies on the dev shell PATH for work-record and git. A record turning inconsistent between check and read exits non-zero under set -e and shows a generic hook error.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An unexpected work-record failure emits a systemMessage naming the cause and still allows the stop
- [ ] #2 The packaged hook finds work-record and git without relying on the caller's PATH, or documents the dependency
<!-- AC:END -->
