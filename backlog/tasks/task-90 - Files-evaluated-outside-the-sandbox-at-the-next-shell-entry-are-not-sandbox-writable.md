---
id: TASK-90
title: Record the accepted risk of sandbox edits evaluated at the next shell entry
status: To Do
assignee: []
created_date: '2026-10-25 01:21'
updated_date: '2026-10-26 01:58'
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
- [ ] #1 docs/workflow/decisions.md records the accepted risk and why
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision (human, 2026-10-25): unavoidable, and the same holds for any source code executed later. Record it as an accepted risk in docs/workflow/decisions.md.
<!-- SECTION:NOTES:END -->
