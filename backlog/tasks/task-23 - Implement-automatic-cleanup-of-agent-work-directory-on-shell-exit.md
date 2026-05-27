---
id: TASK-23
title: Implement automatic cleanup of agent work directory on shell exit
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: medium
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Question from user: does nix have a postShellHook for cleanup? Research: 1) How to create mktemp directory in shellHook, 2) How to ensure cleanup on shell exit (trap? nix hook?), 3) Should cleanup use rm -rf or safer alternative (prevent symlink following), 4) Integration with agent-sandbox.sh. Goal: jail agents to project dir + auto-cleaned temp workspace.
<!-- SECTION:DESCRIPTION:END -->
