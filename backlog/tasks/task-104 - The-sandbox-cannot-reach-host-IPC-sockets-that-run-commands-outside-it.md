---
id: TASK-104
title: The sandbox cannot reach host IPC sockets that run commands outside it
status: In Progress
assignee: []
created_date: '2026-10-28 03:24'
updated_date: '2026-10-28 03:39'
labels:
  - security
  - claude-code
  - opencode
dependencies: []
references:
  - TASK-91
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-91 review. fence on Linux has no Unix socket policy (allowUnixSockets is macOS-only); only denyRead hides a socket path. From inside the sandbox the user systemd bus answered (busctl --user returned the manager Version, StartTransientUnit is exposed), so systemd-run --user likely runs commands outside the sandbox as the user. Mask the known escape sockets and audit the rest.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 /run/user/$UID/bus and /run/user/$UID/systemd/private are not connectable from inside the sandbox on Linux
- [x] #2 Every Unix socket reachable from inside the sandbox on Linux is listed in tools/SANDBOX.md with a decision (masked, or kept with the reason), including SSH_AUTH_SOCK, gpg-agent, and the system bus
- [ ] #3 A test shows a connect to the masked sockets fails for the masking reason, not any error
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC1 and AC3 await a run of the launch tests outside the sandbox (bats tools/test-agent-sandbox.bats); the sandbox that wrote them cannot start a nested one.
<!-- SECTION:NOTES:END -->
