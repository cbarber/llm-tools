---
id: TASK-108
title: macOS sandbox denies Unix sockets in every network mode
status: To Do
assignee: []
created_date: '2026-10-28 03:40'
labels:
  - follow-up
  - security
dependencies: []
references:
  - TASK-104
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-104 review. In fence's wildcard network mode the macOS Seatbelt profile emits (allow network*), which allows every Unix socket including SSH_AUTH_SOCK; the Linux masks do not apply on macOS. Deny Unix sockets on macOS regardless of network mode, allowing only listed paths.
<!-- SECTION:DESCRIPTION:END -->
