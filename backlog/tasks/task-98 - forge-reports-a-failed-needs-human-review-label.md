---
id: TASK-98
title: forge reports a failed needs-human-review label
status: To Do
assignee: []
created_date: '2026-10-25 02:36'
labels:
  - follow-up
dependencies: []
references:
  - TASK-66
priority: medium
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from PR #200. forge pr create runs gh pr edit --add-label needs-human-review 2>/dev/null || true, so a repository without the label (or any gh failure) leaves an agent PR unlabelled with no message. It should say the label was not applied and why.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A failed label add prints a warning naming the cause and the PR
<!-- AC:END -->
