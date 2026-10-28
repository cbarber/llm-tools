---
id: TASK-89
title: No sandbox-writable directory precedes system paths on the launching PATH
status: In Progress
assignee: []
created_date: '2026-10-25 01:21'
updated_date: '2026-11-01 01:04'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision (human, 2026-10-25): agent-sandbox re-mounts read-only every launching-PATH directory that falls inside a writable sandbox mount.

AC2: the launch test "names planted in writable PATH directories are not run outside the sandbox" in tools/test-agent-sandbox.bats has not run; it needs a launch outside the sandbox (bats tools/test-agent-sandbox.bats).

AC1 and AC2 both wait on the launch test run outside the sandbox: AC1 was checked without launch evidence and is unchecked until "names planted in writable PATH directories are not run outside the sandbox" passes (bats tools/test-agent-sandbox.bats).
<!-- SECTION:NOTES:END -->
