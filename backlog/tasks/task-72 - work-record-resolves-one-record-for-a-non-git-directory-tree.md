---
id: TASK-72
title: work-record resolves one record for a non-git directory tree
status: To Do
assignee: []
created_date: '2026-10-16 03:52'
labels:
  - workflow
  - follow-up
dependencies: []
references:
  - TASK-60
priority: low
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-60 review. Outside git, each subdirectory resolves its own record, so a Stop hook whose cwd is a subdirectory of a non-git working directory will not find the record created at its root.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Subdirectories of a non-git working directory resolve the record created at its root, or the limitation is an explicit documented decision
<!-- AC:END -->
