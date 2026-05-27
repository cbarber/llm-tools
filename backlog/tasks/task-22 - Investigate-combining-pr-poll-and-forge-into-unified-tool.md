---
id: TASK-22
title: Investigate combining pr-poll and forge into unified tool
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: low
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
pr-poll and forge have overlapping responsibilities:
- Both fetch PR data (pr view, pr comments)
- pr-poll duplicates formatting logic that forge has
- Would be cleaner as single tool with subcommands

Investigate if worth combining into:
- forge pr watch (daemon mode)
- forge pr format-thread <comment_id>
- Shared comment formatting/threading logic

Decision: combine if it reduces >100 LOC duplication
<!-- SECTION:DESCRIPTION:END -->
