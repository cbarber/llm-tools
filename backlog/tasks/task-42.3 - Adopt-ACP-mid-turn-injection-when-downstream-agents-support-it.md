---
id: TASK-42.3
title: Adopt ACP mid-turn injection when downstream agents support it
status: To Do
assignee: []
created_date: '2026-09-25 21:33'
labels: []
dependencies: []
references:
  - 'https://github.com/agentclientprotocol/agent-client-protocol/pull/1261'
parent_task_id: TASK-42
priority: low
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Track native queue and steer support for Temper after ACP session/inject is standardized and a supported downstream ACP agent advertises it. Keep the current session/prompt turn-boundary fallback until capability negotiation makes native injection safe.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A released ACP schema and sacp-conductor version define the adopted injection request, response, delivery, and capability contract
- [ ] #2 At least one supported downstream ACP agent advertises injection and passes an end-to-end capability probe
- [ ] #3 Temper negotiates support, forwards or originates injection without blocking the dispatch loop, and preserves the existing prompt-boundary fallback
- [ ] #4 Tests cover queue and steer ordering, unsupported capability fallback, cancellation, and inject acceptance errors
<!-- AC:END -->
