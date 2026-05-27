---
id: TASK-9
title: Explore webhook integration for async PR feedback
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: low
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Research and design webhook-based feedback loop for agent PR workflows.

## Current State
- Agent creates PR via forge
- User reviews manually (CLI or web)
- Agent must poll for comments manually

## Goal
Explore event-driven alternative where PR comments trigger agent notifications.

## Research Questions
1. GitHub webhooks: Can we receive PR comment events?
2. Gitea webhooks: Similar capabilities?
3. Integration patterns:
   - Webhook → Discord → agent notification?
   - Webhook → local service → inject into agent session?
   - Webhook → file/queue → agent polls file?
4. Security: How to authenticate webhook payloads?
5. DX: Does this actually reduce friction vs manual polling?

## Success Criteria
- Document feasible webhook patterns
- Prototype simplest approach
- Decide: worth implementing vs manual check?

## Related
- kimaki Discord bot pattern (reference from earlier research)
- May inform PR polling implementation (separate issue)
<!-- SECTION:DESCRIPTION:END -->
