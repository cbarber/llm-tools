---
id: TASK-69
title: Temper CLI and OpenCode plugin agree on skills with multiple exec blocks
status: To Do
assignee: []
created_date: '2026-10-16 03:41'
labels:
  - workflow
  - follow-up
dependencies: []
references:
  - TASK-59
priority: low
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-59 review. The temper CLI executes every exec block in a skill and prints outputs before the remaining text, while the OpenCode plugin executes only the first block and substitutes it in place. No current skill has more than one block.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both renderers produce the same rendering for a skill with multiple exec blocks
<!-- AC:END -->
