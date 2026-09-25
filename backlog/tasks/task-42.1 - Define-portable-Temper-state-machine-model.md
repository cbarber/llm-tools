---
id: TASK-42.1
title: Define portable Temper state-machine model
status: To Do
assignee: []
created_date: '2026-09-24 01:50'
labels: []
dependencies: []
references:
  - tools/temper-acp/src/lib.rs
  - agents/opencode/plugins/temper.ts
  - 'https://github.com/mdeloof/statig'
  - 'https://github.com/GnomesOfZurich/scxml'
  - 'https://github.com/fruwehq/determa-state-spec'
parent_task_id: TASK-42
priority: medium
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace independently implemented ACP and OpenCode lifecycle semantics with one versioned, declarative machine definition. Generate Rust and TypeScript artifacts plus shared conformance vectors so adapter behavior cannot drift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A versioned YAML or JSON schema defines session states, normalized events, ordered guarded transitions, named actions, and an explicit unhandled-event policy
- [ ] #2 Generation produces typed Rust and TypeScript state/event definitions and transition tables from the same source
- [ ] #3 Transitions are implemented as a synchronous pure reducer that returns ordered host effects; asynchronous work and timers remain adapter-owned
- [ ] #4 The same generated conformance vectors run against the Rust ACP and TypeScript OpenCode adapters
- [ ] #5 Versioned snapshot and restoration semantics are documented and tested
- [ ] #6 Mermaid documentation is generated from the machine definition
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Research conclusion (2026-09-23): do not make a Rust-only proc-macro crate the portable model. Statig is the strongest mature Rust runtime if an implementation dependency is needed. Track SCXML for validation/visualization and Determa State after its alpha format stabilizes. Keep skill trigger matching as a rules layer invoked by the lifecycle machine, not as one state per trigger.
<!-- SECTION:NOTES:END -->
