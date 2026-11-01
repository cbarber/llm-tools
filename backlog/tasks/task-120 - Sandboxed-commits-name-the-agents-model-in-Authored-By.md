---
id: TASK-120
title: Sandboxed commits name the agent's model in Authored-By
status: Done
assignee: []
created_date: '2026-11-01 02:31'
updated_date: '2026-11-01 15:04'
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

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In a Claude Code session, a SessionStart hook exports AUTHORED_BY_MODEL=<model> for later Bash commands by appending 'export AUTHORED_BY_MODEL=...' to the file named by $CLAUDE_ENV_FILE, taking the model from the hook input's 'model' field; when the field is missing (e.g. after /clear or recovery) or CLAUDE_ENV_FILE is unset, it writes nothing and the trailer falls back to the agent alone
- [x] #2 The hooks are wired in agents/claude-code/settings.template.json (not the generated .claude/settings.local.json), and tests cover: model present -> export line written, model absent -> nothing written, a value with shell metacharacters is quoted safely and never evaluated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The trailer names the session-start model; a /model switch is not followed, by decision: the model rarely changes after a prompt starts. CLAUDE_ENV_FILE is delivered only to SessionStart, Setup, CwdChanged and FileChanged, so no PostModelSwitch hook is wired.
<!-- SECTION:NOTES:END -->
