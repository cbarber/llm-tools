---
id: TASK-77
title: mojo-implement writes report Base lines safely in one place
status: To Do
assignee: []
created_date: '2026-10-16 04:28'
labels:
  - workflow
  - follow-up
dependencies: []
references:
  - TASK-62
priority: low
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-62 review. Writing a Base line overwrites an existing report that lacks one (legacy or hand-edited), and the keep-existing-base logic is written twice with initialization parsing it a third way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An existing report without a Base line keeps its content when a base is added
- [ ] #2 Base lines are written and read through one documented command
<!-- AC:END -->
