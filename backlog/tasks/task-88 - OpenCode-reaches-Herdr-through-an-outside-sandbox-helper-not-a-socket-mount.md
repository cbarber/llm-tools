---
id: TASK-88
title: 'OpenCode reaches Herdr through an outside-sandbox helper, not a socket mount'
status: To Do
assignee: []
created_date: '2026-10-25 01:21'
labels:
  - follow-up
  - opencode
  - security
dependencies: []
references:
  - TASK-66
priority: high
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66. agents/opencode passes the Herdr socket into the sandbox via SANDBOX_EXTRA_RO; a read-only bind does not prevent connect(), so the untrusted agent can drive any Herdr pane. TASK-66 moved Claude Code to an outside-sandbox helper (herdr-renew) instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The OpenCode sandbox no longer has the Herdr socket
- [ ] #2 Whatever OpenCode needs from Herdr goes through a helper outside the sandbox that validates its requests
<!-- AC:END -->
