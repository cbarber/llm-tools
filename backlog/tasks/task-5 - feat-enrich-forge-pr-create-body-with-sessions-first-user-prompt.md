---
id: TASK-5
title: 'feat: enrich forge pr create body with session''s first user prompt'
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - feature
dependencies: []
priority: high
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OpenCode stores session history in SQLite at ~/.local/share/opencode/opencode-stable.db (stable channel) or opencode.db. Schema: session (id, directory, title) -> message (id, session_id, role) -> part (data JSON blob containing type/text fields).

Investigation of ses_2f421a2a1ffeqAQdZGxJx4C9tm (Mar 21 session) revealed the agent asked 'Push?' 6 times in one session despite clean state each time — confirming the workflow gap where no instruction drives autonomous push after quality gates pass.

The session's first user-role text part is the task description — the WHY behind the PR. forge pr create should query the OpenCode DB for the current session's first user prompt (OPENCODE_SESSION_ID env var is already injected by the temper plugin's shell.env hook) and include it in the PR body automatically.

Query to extract first user prompt:
  SELECT p.data FROM part p
  JOIN message m ON p.message_id = m.id
  WHERE m.session_id = 'SESSION_ID'
  AND m.role = 'user'
  AND json_extract(p.data, '$.type') = 'text'
  AND json_extract(p.data, '$.synthetic') IS NULL
  ORDER BY p.time_created ASC LIMIT 1;

Implementation notes:
- DB path differs between channels: opencode-stable.db (stable) vs opencode.db (dev). Try stable first, fall back to dev.
- OPENCODE_SESSION_ID is set via temper plugin shell.env hook — use it to scope the query
- Only enriches when running inside OpenCode with OPENCODE_SESSION_ID set; graceful no-op otherwise
- First prompt may be long — consider truncation or using it verbatim as the PR body WHY section
- sqlite3 must be available; check with command -v sqlite3 before attempting
<!-- SECTION:DESCRIPTION:END -->
