---
id: TASK-99
title: Worker and reviewer rules live in the instructions
status: To Do
assignee: []
created_date: '2026-10-26 01:58'
updated_date: '2026-10-26 02:20'
labels:
  - workflow
dependencies: []
references:
  - TASK-61
  - TASK-62
priority: high
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The implementer brief only pointed at mojo-commit, nothing verified it was followed, and 36 commits shipped without the Authored-By trailer. mojo-commit also tells agents to push and open a PR without asking, contradicting the brief's no-push rule. Briefs must carry the rules themselves, and the coordinator and reviewer must check them. Subsumes TASK-79 and TASK-92. Fixes to branch commits land as fixup! commits on their owning commit; mojo-commit is on main, so its fix is a new commit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The implementer brief states the commit rules it relies on (Conventional Commits form, Authored-By trailer, one concern per commit, fixup targeting) rather than only naming mojo-commit
- [ ] #2 Implementer, reviewer and mojo-review axis sub-agent briefs carry the standing rules, including the commands that prompt even in bypass mode (rm on variable or glob paths, reading or writing ~/.claude or .claude/, Herdr sockets) and a scratch dir left in place
- [ ] #3 Reconciliation checks each new commit's trailer and the standing rules against Git, and mojo-review's Standards axis checks the trailer
- [ ] #4 mojo-commit no longer instructs a worker to push or open a PR; publishing belongs to the coordinator's or human's step
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Revised 2026-10-25: TASK-101 makes the sandbox add the Authored-By trailer, so briefs only note that it is automatic and reconciliation checks it is present; the rest stands.
<!-- SECTION:NOTES:END -->
