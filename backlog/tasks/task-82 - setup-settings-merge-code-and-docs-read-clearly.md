---
id: TASK-82
title: setup-settings merge code and docs read clearly
status: To Do
assignee: []
created_date: '2026-10-16 18:16'
labels:
  - claude-code
  - follow-up
dependencies: []
references:
  - TASK-63
priority: low
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-63 review. jq helper names (m3, field, pick, key) don't say what they do; the MERGE comment explains how rather than why; the first-run message still says 'Created settings.json with Claude Code hooks (notify)'; .claude/.settings.local.base.json is missing from CLAUDE.md's generated-files table; possible speculative schema fallbacks noted in round 0.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 jq helpers have descriptive names and the MERGE comment states why in a few facts
- [ ] #2 First-run message names settings.local.json accurately
- [ ] #3 CLAUDE.md Configuration table lists the merge base file
<!-- AC:END -->
