---
id: TASK-113
title: Agent sandbox PATH check does not cache a failed readlink as an empty target
status: To Do
assignee: []
created_date: '2026-11-01 02:28'
labels:
  - follow-up
dependencies: []
references:
  - TASK-89
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-89 review. If a link changes between the existence test and readlink, the readlink cache stores an empty target and later checks trust it. Treat a failed readlink as a refusal or leave it uncached.
<!-- SECTION:DESCRIPTION:END -->
