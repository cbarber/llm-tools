---
id: TASK-106
title: Socket masks survive the host recreating the socket
status: To Do
assignee: []
created_date: '2026-10-28 03:40'
labels:
  - follow-up
  - security
dependencies: []
references:
  - TASK-104
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-104 review. fence masks a single socket file with a /dev/null bind. Unlinking a mount point in another mount namespace detaches the mount (Linux 3.18+), so a service restart, socket reactivation, or a new ssh-agent likely exposes the recreated socket (bus, systemd/private, systemd/io.systemd.Manager, gcr/ssh, SSH_AUTH_SOCK) to a running sandbox. Verify outside the sandbox; if confirmed, mask parent directories or otherwise make the masks hold.
<!-- SECTION:DESCRIPTION:END -->
