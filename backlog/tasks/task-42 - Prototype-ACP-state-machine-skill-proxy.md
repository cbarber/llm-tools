---
id: TASK-42
title: Prototype ACP state-machine skill proxy
status: Done
assignee: []
created_date: '2026-09-08 02:01'
updated_date: '2026-09-11 03:59'
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
- [x] #1 Conductor launches one state-machine proxy and a configurable ACP agent
- [x] #2 Proxy records session, prompt, cancellation, tool-call, and turn-completion events
- [x] #3 State transitions can prepend configured skill text to the next prompt
- [x] #4 Tests cover session isolation, cancellation, and prompt injection
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in PR #182 with a configurable Symposium conductor, session-scoped Temper ACP proxy, lifecycle and cancellation handling, prompt injection, and unit coverage. Verified by cargo fmt, Clippy, cargo test, shellcheck, nixfmt, Nix package builds, and CI run 34560117525.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added the ACP v1 state-machine proxy and integrated it into the Cursor CLI runtime.
<!-- SECTION:FINAL_SUMMARY:END -->
