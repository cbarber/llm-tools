---
id: TASK-43
title: Stabilize macOS pre-commit package test in CI
status: To Do
assignee: []
created_date: '2026-09-08 03:26'
updated_date: '2026-09-08 14:07'
labels: []
dependencies: []
priority: medium
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #182 CI run 34182815109 failed while building nixpkgs pre-commit 4.5.1 on macOS: upstream tests/repository_test.py::test_output_isatty failed after 714 tests passed. The same branch tree passed in run 34178708190 before commit-message-only rewrites. Determine whether to disable the flaky upstream check, pin/fix the package, or increase CI resilience.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-08: Fresh CI run 34183578649 passed the same macOS sandbox job in 15m56s after the prior run failed in pre-commit's test_output_isatty, confirming the failure is intermittent. Direct rerun of the failed run was unavailable to the current token, so the tracking commit triggered a new run.
<!-- SECTION:NOTES:END -->
