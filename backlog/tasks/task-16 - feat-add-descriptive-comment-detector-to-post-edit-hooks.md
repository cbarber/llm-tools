---
id: TASK-16
title: 'feat: add descriptive comment detector to post-edit hooks'
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - feature
dependencies: []
priority: medium
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents consistently write descriptive 'what' comments that narrate what code does rather than explain why. These are net negative: noise at best, actively misleading when code changes without updating them (drift). No existing project linter catches this — it requires agent-specific detection.

Build tools/check-comments (Python) that reads a unified diff from stdin:
1. Extract added lines (+) that are comments (#, //, /*, *)
2. WHY-exclusion first: skip if contains because/since/workaround/required/avoid/legacy/etc
3. WHAT-detection: flag imperative verbs (Get/Set/Create/Check/Loop/Run/etc) with no causal language, and bare noun-phrase section headers
4. Output file:line: descriptive comment: '<text>' per violation, exit 1

The imperative verb list should live in a shared file (e.g. tools/agent-lint-verbs.txt) — the same list is needed by the commit message linter (llm-tools-sjd) and potentially the duplicate code detector (llm-tools-nfl).

Wire into OpenCode tool.execute.after (pipe diff through script, inject noReply:false message on violation) and Claude Code PostToolUse (exit 2 blocks).
Package in tools/default.nix. Validate against known violations: tools/update-package.sh (16 instances), tools/agent-sandbox.sh (20+), .opencode/plugin/temper/index.ts (10).
<!-- SECTION:DESCRIPTION:END -->
