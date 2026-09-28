---
id: TASK-42.2.4
title: Cover Temper upgrades and workflow regressions
status: To Do
assignee: []
created_date: '2026-09-28 21:44'
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
- [ ] #1 Installing temper.js removes or disables an obsolete temper.ts entrypoint so OpenCode loads one Temper plugin.
- [ ] #2 Setup-config tests cover upgrades from an existing TypeScript plugin installation.
- [ ] #3 CI runs workflow runtime, adapter, provider, restore, graph rejection, permissions, stop, cleanup, and mismatch tests.
<!-- AC:END -->
