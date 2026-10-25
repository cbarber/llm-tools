---
id: TASK-94
title: Warn when the transcript tail has no main-chain usage
status: To Do
assignee: []
created_date: '2026-10-25 02:11'
labels:
  - follow-up
dependencies: []
references:
  - TASK-66
priority: low
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66 final review. context_tokens reads tail -n 500 of the transcript; with no main-chain usage there it returns 0 silently and renewal is skipped, at odds with decisions.md (unreadable transcript is reported, not ignored).
<!-- SECTION:DESCRIPTION:END -->
