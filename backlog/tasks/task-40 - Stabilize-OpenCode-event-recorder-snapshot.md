---
id: TASK-40
title: Stabilize OpenCode event recorder snapshot
status: To Do
assignee: []
created_date: '2026-08-22 21:52'
labels: []
dependencies: []
priority: medium
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The OpenCode 1.18.21 event recorder snapshot asserts ordering among asynchronous integration.updated, catalog.updated, and session.status events. Repeated isolated runs produce different valid orders, making the full harness flaky. Normalize or separately assert these unordered startup events.
<!-- SECTION:DESCRIPTION:END -->
