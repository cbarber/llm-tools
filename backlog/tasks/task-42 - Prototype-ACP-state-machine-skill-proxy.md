---
id: TASK-42
title: Prototype ACP state-machine skill proxy
status: To Do
assignee: []
created_date: '2026-09-08 02:01'
labels: []
dependencies: []
references:
  - 'https://agentclientprotocol.com/rfds/proxy-chains'
  - 'https://github.com/agentclientprotocol/rust-sdk'
priority: medium
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a stable ACP v1 proof of concept that runs between a generic ACP client and an ACP agent, observes session and tool lifecycle events, maintains session-scoped state, and injects selected skill instructions at the next session/prompt boundary. Base it on agentclientprotocol/rust-sdk conductor and proxy APIs; defer ACP v2 and mid-turn session/inject.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Conductor launches one state-machine proxy and a configurable ACP agent
- [ ] #2 Proxy records session, prompt, cancellation, tool-call, and turn-completion events
- [ ] #3 State transitions can prepend configured skill text to the next prompt
- [ ] #4 Tests cover session isolation, cancellation, and prompt injection
<!-- AC:END -->
