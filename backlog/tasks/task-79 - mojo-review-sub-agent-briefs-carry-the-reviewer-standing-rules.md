---
id: TASK-79
title: mojo-review sub-agent briefs carry the reviewer standing rules
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
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-62 review. mojo-review's axis sub-agent templates omit the reviewer's standing rules (read-only checkout, no work-record writes, scratch-only WORK_RECORD_HOME); reviewers had to add them by hand.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each axis sub-agent brief includes the standing rules verbatim
<!-- AC:END -->
