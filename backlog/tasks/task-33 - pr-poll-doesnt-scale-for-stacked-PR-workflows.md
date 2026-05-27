---
id: TASK-33
title: pr-poll doesn't scale for stacked PR workflows
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: medium
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
pr-poll only monitors PRs mentioned in session messages. For stacked PRs (14+ PRs per branch), most PRs are invisible. Need to discover PRs via spr status or GitHub API instead of session scraping.
<!-- SECTION:DESCRIPTION:END -->
