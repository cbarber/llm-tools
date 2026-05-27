---
id: TASK-11
title: Document interactive rebase commit injection technique as skill
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: low
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
During stacked PR work, we discovered powerful git techniques for inserting commits into history:

1. GIT_SEQUENCE_EDITOR='sed -i "1s/^pick/edit/"' git rebase -i <commit>^ - inject commit after specific SHA
2. GIT_EDITOR=true git rebase --continue - bypass vim prompts
3. amend! commits for non-interactive message rewording

These should be documented as a skill or agent prompt pattern. Particularly useful for:
- Fixing commits deep in PR stack without manual interactive rebase
- Automating git workflows in agent environments
- Rewriting commit messages without interactive prompts

See AGENTS.md commit workflow section for current documentation.
<!-- SECTION:DESCRIPTION:END -->
