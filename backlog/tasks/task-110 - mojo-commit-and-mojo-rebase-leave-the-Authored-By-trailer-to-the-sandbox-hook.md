---
id: TASK-110
title: mojo-commit and mojo-rebase leave the Authored-By trailer to the sandbox hook
status: To Do
assignee: []
created_date: '2026-11-01 02:22'
labels:
  - skills
dependencies: []
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
mojo-commit (SKILL.md:64, example :73) and mojo-rebase (SKILL.md:44-48) tell agents to write Authored-By by hand, with a claude-3.7-sonnet example. Since TASK-101 the sandbox hook adds it, and it keeps an existing trailer, so a copied example leaves the wrong model name. Human request 2026-10-31.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Neither skill tells agents to write Authored-By by hand or shows a hard-coded model
- [ ] #2 Both say the sandbox adds the trailer, and what to do outside the sandbox
<!-- AC:END -->
