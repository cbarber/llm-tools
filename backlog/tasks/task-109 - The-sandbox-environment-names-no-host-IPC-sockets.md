---
id: TASK-109
title: The sandbox environment names no host IPC sockets
status: To Do
assignee: []
created_date: '2026-10-28 03:40'
labels:
  - follow-up
  - security
dependencies: []
references:
  - TASK-104
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-104 review. DBUS_SESSION_BUS_ADDRESS, SSH_AUTH_SOCK, DISPLAY, WAYLAND_DISPLAY and HERDR_SOCKET_PATH still reach the sandbox. They name masked paths, so clients fail to connect, but unsetting them removes the pointer and any reliance on the mask.
<!-- SECTION:DESCRIPTION:END -->
