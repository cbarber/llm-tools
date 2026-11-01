---
id: TASK-124
title: Skill installs from different checkouts do not undo each other
status: To Do
assignee: []
created_date: '2026-11-01 02:40'
labels:
  - follow-up
dependencies: []
references:
  - TASK-111
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-111 review. One ~/.agents/skills/.llm-tools-installed manifest is shared by every checkout and branch: entering an older branch removes skills only newer branches have, even while their sessions use them. Ownership is by name, so a repo skill sharing a name with another source's skill merges with it and deleting it later removes the other source's files.
<!-- SECTION:DESCRIPTION:END -->
