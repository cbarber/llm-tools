---
id: TASK-30
title: 'feat: add duplicate code detection to post-edit hooks'
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - feature
dependencies: []
priority: medium
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents write utility functions that already exist elsewhere in the repo — a working-memory failure where the agent forgets what it wrote earlier in the session or what already existed. No project linter catches this. Requires agent-specific duplicate detection.

Architecture decision: project lint (eslint, ruff, shellcheck) is separate from agent lint. This is agent lint.

Build tools/check-duplicates (shell wrapper around jscpd) that:
1. Reads unified diff from stdin, extracts modified file paths
2. Runs jscpd across the whole repo (--min-tokens 50 --reporters json)
3. Filters jscpd JSON output to violations involving at least one modified file
4. Output file:line: duplicate of file:line per violation, exit 1

The whole-repo scan is intentional — the agent failure mode is writing something that already exists in an unmodified file, not just within the current edit. jscpd added to tools/default.nix as pkgs.jscpd.

Wire into OpenCode tool.execute.after and Claude Code PostToolUse alongside check-comments (llm-tools-anp). Package in tools/default.nix.
<!-- SECTION:DESCRIPTION:END -->
