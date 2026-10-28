---
id: TASK-105
title: The sandbox gets a private /tmp and only allowlisted /run paths
status: To Do
assignee: []
created_date: '2026-10-28 03:40'
updated_date: '2026-10-28 03:42'
labels:
  - follow-up
  - security
dependencies: []
references:
  - TASK-104
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-104 review. agent-sandbox.sh binds host /tmp read-write and fence binds all of /run unless strictDenyRead is set. Reachable as a result: other sessions' fence proxy bridges (bypass this session's network filter and may carry their credential injection), Chromium SingletonSocket, and any socket not on the deny list or created after launch (Neovim nvim.*.0 servers, kitty, WezTerm, Zellij, Emacs server). Set strictDenyRead with an explicit allowlist of the /run paths the sandbox needs and give it a private /tmp; verify with a launch outside the sandbox.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-104 re-review: fence expands absolute globs in denyRead at launch (ExpandGlobPatterns, internal/sandbox/linux_landlock.go:515), so /tmp/scoped_dir*/SingletonSocket and $RUNTIME/nvim.*.0 can be masked if present at launch; later sockets still need the structural fix. Link the SANDBOX.md Gaps bullets to TASK-105..109.
<!-- SECTION:NOTES:END -->
