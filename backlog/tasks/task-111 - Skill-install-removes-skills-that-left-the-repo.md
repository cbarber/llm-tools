---
id: TASK-111
title: Skill install removes skills that left the repo
status: In Progress
assignee: []
created_date: '2026-11-01 02:22'
updated_date: '2026-11-01 02:33'
labels:
  - skills
dependencies: []
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
tools/setup-shared-shell.sh:12-18 installs skills with rsync and never deletes. Skills removed from the repo stay installed and discoverable: mojo-create-pull-request, mojo-update-pull-request and mojo-review-response from the failed cmb/fsm branch tell agents to push and open PRs without asking. Remove only skills this repo installed; never rm -rf the whole skills directory (other sources install there too).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A skill deleted from agents/skills is removed from the install target on the next shell entry
- [x] #2 Skills not installed from this repo are left untouched
- [ ] #3 The three stale fsm-era skills are gone after the next shell entry
<!-- AC:END -->
