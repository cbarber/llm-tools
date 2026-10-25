---
id: TASK-91
title: Decide how the sandbox relates to the trusted Nix daemon user
status: To Do
assignee: []
created_date: '2026-10-25 01:21'
labels:
  - follow-up
  - claude-code
  - opencode
  - security
dependencies: []
references:
  - TASK-66
priority: high
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-66 reviews. trusted-users includes the user and the sandbox reaches the Nix daemon (nix store info reports Trusted: 1), which is root-equivalent: it can import store paths with arbitrary contents. Human decision on the fix (untrusted daemon access from the sandbox, no daemon socket, or accepted risk).

Leading option: an untrusted proxy daemon for the sandbox. The user stays trusted. Root runs a second daemon, e.g. a NixOS socket and service unit for `nix daemon --force-untrusted --store daemon`. Its help (Nix 2.34.8) says such a connection "is processed by the receiving daemon before forwarding commands", so it treats every client as untrusted and forwards to the real daemon. tools/agent-sandbox.sh mounts that socket at /nix/var/nix/daemon-socket/socket in place of the real one, so the agent can still build. Untested.

Alternatives:
- Drop cbarber from trusted-users, and add extra caches system-wide via substituters or trusted-substituters with trusted-public-keys. This also takes trust away from the user's own terminal.
- Run the sandbox as a real second uid. A user namespace maps back to cbarber, so a different uid inside the namespace is not enough, and checkout files would be owned by another uid.
- Give the sandbox no daemon socket, so there is no Nix inside it.
- Accept the risk.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The decision is recorded in docs/workflow/decisions.md
- [ ] #2 The sandbox's daemon access matches the decision
- [ ] #3 Unless the risk is accepted, `nix store info` inside the sandbox reports Trusted: 0, and nix build still works there
<!-- AC:END -->
