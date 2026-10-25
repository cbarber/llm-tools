---
id: TASK-80
title: >-
  mojo-implement correction rounds back out failed fixups and show mid-round
  state
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
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-62 review. 'Drop what fails verification' has no mechanism because fixups are cherry-picked before verification with no pre-apply head noted; the range-diff anchor is taken after cherry-picks; after renewal mid round 3, initialization reports the bound as reached before that round's re-review has run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A fixup that fails verification is removed without disturbing accepted ones
- [ ] #2 Initialization distinguishes a round in progress from a completed round at the bound
<!-- AC:END -->
