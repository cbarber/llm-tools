---
id: TASK-112
title: Agent sandbox checks every PATH entry when PATH contains a newline
status: To Do
assignee: []
created_date: '2026-11-01 02:28'
labels:
  - follow-up
dependencies: []
references:
  - TASK-89
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-89 review. A newline in the launching PATH variable stops the IFS=: read in agent-sandbox.sh, so entries after it are never checked. Refuse the launch or check every entry.
<!-- SECTION:DESCRIPTION:END -->
