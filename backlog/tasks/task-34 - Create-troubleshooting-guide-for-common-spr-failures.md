---
id: TASK-34
title: Create troubleshooting guide for common spr failures
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: low
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
During the stacked PR epic, we encountered several spr failure modes:

COMMON FAILURES:
1. Expired GitHub token → spr segfault (llm-tools-0ae)
2. Branch names with slashes → spr fails to parse
3. Branch not tracking origin/main → spr compares to wrong base
4. Someone merges via GitHub UI → stack breaks
5. Force push conflicts → need --force-with-lease understanding

NEEDED:
- Troubleshooting guide with error messages and solutions
- Pre-flight checks before spr update (token valid, branch tracking correct)
- Recovery procedures (rebase onto new main, rebuild stack)
- Clear error messages when spr fails (not segfaults)

This would prevent lost time debugging the same issues repeatedly.
<!-- SECTION:DESCRIPTION:END -->
