---
id: TASK-102
title: mojo-complete leaves publishing to the coordinator
status: To Do
assignee: []
created_date: '2026-10-28 02:39'
labels:
  - follow-up
dependencies: []
references:
  - TASK-99
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-99 review. mojo-complete still says "Work is NOT done until pushed" and force-pushes, which contradicts the worker rule that only the coordinator publishes. Under mojo-implement, workers must stop and report instead of pushing.
<!-- SECTION:DESCRIPTION:END -->
