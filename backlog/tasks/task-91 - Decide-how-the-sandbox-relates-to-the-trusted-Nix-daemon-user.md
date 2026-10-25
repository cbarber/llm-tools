---
id: TASK-91
title: Decide how the sandbox relates to the trusted Nix daemon user
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
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66 reviews. trusted-users includes the user and the sandbox reaches the Nix daemon (nix store info reports Trusted: 1), which is root-equivalent: it can import store paths with arbitrary contents. Human decision on the fix (untrusted daemon access from the sandbox, no daemon socket, or accepted risk).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The decision is recorded in docs/workflow/decisions.md
- [ ] #2 The sandbox's daemon access matches the decision
<!-- AC:END -->
