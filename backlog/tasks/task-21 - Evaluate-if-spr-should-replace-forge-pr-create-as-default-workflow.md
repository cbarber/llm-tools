---
id: TASK-21
title: Evaluate if spr should replace forge pr create as default workflow
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: low
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
We successfully dog-fooded spr workflow (15 PRs landed). Key benefits:

ADVANTAGES:
- Each commit = independent PR (parallel review)
- Automatic stack management (spr update, spr merge)
- Easy reordering/editing via git rebase
- Clear dependency visualization (spr status)
- Forces atomic commits (each must stand alone)

TRADE-OFFS:
- Learning curve (different from forge pr create)
- Requires understanding of git rebase --autosquash
- Branch must track origin/main (not intuitive)
- Stack breaks if anyone merges via GitHub UI
- More complex for simple single-commit PRs

QUESTIONS:
1. Should AGENTS.md default to spr workflow?
2. When to use forge pr create vs spr?
3. Should temper pr workflow template switch to spr?
4. Does this work well with protected branches/CODEOWNERS?

Decision impacts agent prompts, documentation, and new user experience.
<!-- SECTION:DESCRIPTION:END -->
