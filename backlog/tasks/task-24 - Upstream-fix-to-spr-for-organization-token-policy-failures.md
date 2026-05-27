---
id: TASK-24
title: Upstream fix to spr for organization token policy failures
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: low
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
spr crashes when GitHub API token violates organization policies (e.g., mojotech requires tokens ≤366 days lifetime). The crash occurs during GetInfo() which fetches ALL user PRs across ALL orgs, even when working in an unrelated repo.

Issues:
1. spr panics instead of gracefully handling API errors from org policy violations
2. spr queries PRs from all orgs even when only working in one repo
3. Similar issue occurs with expired tokens - spr crashes instead of helpful error

Upstream fix should:
1. Handle API errors gracefully (don't panic on org policy violations)
2. Filter PR queries to relevant repos/orgs only
3. Provide actionable error messages for token issues

References:
- Error: viewer.pullRequests.nodes: The 'mojotech' organization forbids access via fine-grained personal access tokens if token lifetime > 366 days
- Similar expired token crash reported previously
<!-- SECTION:DESCRIPTION:END -->
