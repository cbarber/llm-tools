---
id: TASK-89
title: No sandbox-writable directory precedes system paths on the launching PATH
status: To Do
assignee: []
created_date: '2026-10-25 01:21'
labels:
  - follow-up
  - claude-code
  - opencode
  - security
dependencies: []
references:
  - TASK-66
priority: high
ordinal: 88000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66 reviews. .direnv/bin (in the checkout) and ~/.cargo/bin are writable from the sandbox and come before /run/current-system/sw/bin on the user's PATH, so anything the shell later runs by bare name outside the sandbox can be planted. TASK-66 avoids PATH for its own commands; the shells in general do not.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Commands the agent shells run outside the sandbox cannot resolve to a file the sandbox can write
- [ ] #2 A test plants a name in each sandbox-writable PATH dir and shows it is not run
<!-- AC:END -->
