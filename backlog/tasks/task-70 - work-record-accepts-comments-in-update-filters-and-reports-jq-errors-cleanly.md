---
id: TASK-70
title: work-record accepts comments in update filters and reports jq errors cleanly
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
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-60 review. A trailing # comment in a record filter swallows the wrapper the helper appends, causing a syntax error; jq stderr is merged into the captured record text, so a warning on an otherwise valid update is misreported as invalid JSON.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A record filter ending in a # comment applies normally
- [ ] #2 jq diagnostics are reported separately from the updated record
<!-- AC:END -->
