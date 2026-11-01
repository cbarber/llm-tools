---
id: TASK-120
title: Sandboxed commits name the agent's model in Authored-By
status: To Do
assignee: []
created_date: '2026-11-01 02:31'
labels:
  - follow-up
dependencies: []
references:
  - TASK-101
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-110 review. tools/git-hooks/authored-by-trailer writes 'Authored-By: $agent ($AUTHORED_BY_MODEL)', but no shell sets AUTHORED_BY_MODEL (only AUTHORED_BY_AGENT, in agents/*/setup-shell.sh), so real commits get 'Authored-By: claude-code' with no model while skills promise '<agent> (<model>)'. Decide where the model comes from (it can change mid-session) or drop '(<model>)' from the documented form.
<!-- SECTION:DESCRIPTION:END -->
