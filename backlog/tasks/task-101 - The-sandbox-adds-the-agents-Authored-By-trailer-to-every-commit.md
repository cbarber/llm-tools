---
id: TASK-101
title: The sandbox adds the agent's Authored-By trailer to every commit
status: Done
assignee: []
created_date: '2026-10-26 02:20'
updated_date: '2026-10-28 02:27'
labels:
  - security
dependencies: []
references:
  - TASK-99
priority: high
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agent commits shipped without the Authored-By trailer because only instructions asked for it. Inside the sandbox only, agent-sandbox points git at a read-only hooks directory in the Nix store through GIT_CONFIG_COUNT/GIT_CONFIG_KEY_n/GIT_CONFIG_VALUE_n (not the user's git config), and its prepare-commit-msg hook appends Authored-By: <agent> (<model>) with git interpret-trailers --if-exists addIfDifferent. --no-verify does not skip prepare-commit-msg. The agent name comes from the agent's shell setup (claude-code, opencode); the model is included only when the environment provides it. agent-sandbox predates this branch, so this is a new commit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A commit made inside the sandbox, including with --no-verify and with -m, carries exactly one Authored-By trailer naming the agent
- [x] #2 Amending a commit that already has the trailer does not duplicate it
- [x] #3 Commits made outside the sandbox are untouched, and the hooks directory is not writable from the sandbox
- [x] #4 A bats test covers each case
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Known limits (accepted): a replay the agent alters keeps the original message and its Reviewed-By, with no stamp, when (1) a conflict resolution moves the original's lines elsewhere (patch-id ignores position), or (2) it goes through git am or rebase --apply, which never run prepare-commit-msg.
<!-- SECTION:NOTES:END -->
