---
id: TASK-42.2.4
title: Cover Temper upgrades and workflow regressions
status: In Progress
assignee: []
created_date: '2026-09-28 21:44'
updated_date: '2026-09-30 21:37'
labels: []
dependencies: []
references:
  - agents/opencode/setup-config.sh
  - .github/workflows/test-agent-harness.yml
parent_task_id: TASK-42.2
priority: high
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prevent duplicate plugin loading during the temper.ts-to-temper.js migration and run the complete workflow suite in CI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Installing temper.js removes or disables an obsolete temper.ts entrypoint so OpenCode loads one Temper plugin.
- [x] #2 Setup-config tests cover upgrades from an existing TypeScript plugin installation.
- [ ] #3 CI runs workflow runtime, adapter, provider, restore, graph rejection, permissions, stop, cleanup, and mismatch tests.
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-29 18:43
---
Setup-config removes the obsolete temper.ts when temper.js is installed; Bats covers this upgrade. CI includes plugin tests, but fixture and OpenCode E2E coverage for restore mismatch, permissions, cleanup, and idle remain incomplete.
---

created: 2026-09-30 21:37
---
Restore-hash mismatch is covered at the adapter seam; stale state is removed and fresh activation succeeds. The Mojo workflow integration also records delivered skills, prefers the project workflow, and avoids legacy completion and unrelated dirty-state prompts. Criterion #3 remains in progress.
---
<!-- COMMENTS:END -->
