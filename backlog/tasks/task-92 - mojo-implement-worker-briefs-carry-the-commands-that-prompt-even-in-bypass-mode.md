---
id: TASK-92
title: >-
  mojo-implement worker briefs carry the commands that prompt even in bypass
  mode
status: To Do
assignee: []
created_date: '2026-10-25 01:21'
labels:
  - follow-up
  - skills
dependencies: []
references:
  - TASK-66
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66. Workers ran rm -rf on a temp dir held in a variable and touched ~/.claude, both of which make Claude Code ask the user even with --dangerously-skip-permissions. The coordinator added the rules to briefs by hand. Companion to TASK-79 for reviewers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The mojo-implement brief template forbids rm on variable or glob paths and reading or writing ~/.claude or .claude/, and points scratch work at a scratch dir left in place
<!-- AC:END -->
