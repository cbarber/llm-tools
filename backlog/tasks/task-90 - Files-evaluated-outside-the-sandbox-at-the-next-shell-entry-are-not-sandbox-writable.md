---
id: TASK-90
title: >-
  Files evaluated outside the sandbox at the next shell entry are not
  sandbox-writable
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
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66 reviews. The sandbox can edit flake.nix, .envrc and .env in the checkout; the next nix develop / direnv load evaluates or sources them outside the sandbox (setup-shared-shell.sh sources .env), so the agent can run code or set HERDR_RENEW_HERDR/HERDR_RENEW_PATH there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Edits the sandbox makes to these files cannot run code outside it without the human seeing them first
<!-- AC:END -->
