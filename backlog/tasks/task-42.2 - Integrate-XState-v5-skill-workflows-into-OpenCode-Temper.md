---
id: TASK-42.2
title: Integrate XState v5 skill workflows into OpenCode Temper
status: To Do
assignee: []
created_date: '2026-09-25 20:15'
labels: []
dependencies: []
references:
  - agents/opencode/plugins/temper.ts
  - agents/opencode/setup-config.sh
  - agents/opencode/default.nix
  - tools/setup-sandbox-paths.sh
  - 'https://stately.ai/docs/graph'
  - 'https://stately.ai/docs/persistence'
parent_task_id: TASK-42
priority: medium
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add an OpenCode-specific XState v5 workflow runtime to Temper. A trusted workflow.ts adjacent to a discovered SKILL.md activates when that skill is loaded, with at most one active workflow per OpenCode session. Preserve existing trigger dispatch while adding validated transitions, rendered skill effects, restart-safe snapshots, secure traces, idle continuation, and manual stop.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Use app.skills({ directory }) as the authoritative source for project and global skill discovery, and dynamically import only the activated skill's adjacent workflow.ts.
- [ ] #2 Pin XState v5 and validate each machine with xstate/graph using bounded traversal and representative events before activation.
- [ ] #3 Allow one active workflow per session, serialize session events, implement a cancellable five-second host-owned idle timer, and provide a temper_workflow_stop tool.
- [ ] #4 Implement a named transition effect that resolves, renders, concatenates, and injects skills in order, including all bash {exec} blocks.
- [ ] #5 Persist actor snapshots outside the repository with a versioned envelope containing workflow ID, version, source hash, and directory; discard incompatible or malformed snapshots.
- [ ] #6 Write redacted per-session JSONL traces under the OpenCode state directory with directories mode 0700 and files mode 0600.
- [ ] #7 Package XState reproducibly in Nix, make it resolvable by Bun-loaded workflow files, and retain the one-file installed Temper entrypoint.
- [ ] #8 Cover discovery, graph rejection, exclusivity, idle cancellation, effects, restore mismatch, permissions, manual stop, and cleanup in tests.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Use buildNpmPackage to produce a Bun-bundled Temper entrypoint while keeping xstate external and available through NODE_PATH. Add focused workflow runtime and store modules behind temper.ts. Use machine.provide() to capture temper.renderSkills actions synchronously, process effects after actor.send(), then atomically persist actor.getPersistedSnapshot(). Restore with createActor(machine, { snapshot }) only after envelope validation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Research completed 2026-09-25. Pin xstate 5.33.2; graph utilities are provided by xstate/graph, not @xstate/graph. Restrict the first implementation to synchronous event-driven machines: no invoke, spawned actors, or XState after delays. Dynamic TypeScript imports are an explicit trust boundary. Entry-source hashing does not cover imported dependency changes, so workflow authors must bump the explicit version.
<!-- SECTION:NOTES:END -->
