---
id: TASK-107
title: Abstract sockets are unreachable in every network mode
status: To Do
assignee: []
created_date: '2026-10-28 03:40'
labels:
  - follow-up
  - security
dependencies: []
references:
  - TASK-104
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-104 review. Abstract Unix sockets have no path to mask. With allowedDomains ["*"] and no credential proxy, fence skips --unshare-net, so host abstract sockets such as @/tmp/.X11-unix/X0 (keystroke injection) are reachable. Ensure the sandbox always has its own network namespace on Linux, or record the mode as unsupported.
<!-- SECTION:DESCRIPTION:END -->
