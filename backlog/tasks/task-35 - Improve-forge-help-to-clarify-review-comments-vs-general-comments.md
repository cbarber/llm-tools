---
id: TASK-35
title: Improve forge help to clarify review comments vs general comments
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: medium
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agent confusion: tried to use 'forge pr comment' to reply to code review comments, but it only posts general PR comments. The distinction between review comments (file/line) and general comments isn't clear.

Current help shows:
  pr comment [NUMBER] TEXT
  pr review-comments [NUMBER] [--json]

Issues:
1. Doesn't clarify that 'pr comment' posts general comments only
2. Doesn't explain that review-comments is read-only
3. No guidance on how to reply to review comments
4. Missing common workflow examples

Improvements:
1. Add clarifying descriptions:
   pr comment [NUMBER] TEXT            # Post general PR comment (not threaded reply)
   pr review-comments [NUMBER]         # View code review comments (read-only)

2. Add --examples flag with common workflows
3. Better error messages suggesting correct commands
4. Document limitations (if review replies aren't supported)

Real-world agent mistake:
- Wanted to reply to specific review comment on line 33
- Used 'pr comment' thinking it would thread the reply
- Actually posted general comment instead
- Should have been guided to correct approach
<!-- SECTION:DESCRIPTION:END -->
