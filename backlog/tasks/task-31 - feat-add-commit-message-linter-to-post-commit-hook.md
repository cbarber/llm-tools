---
id: TASK-31
title: 'feat: add commit message linter to post-commit hook'
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - feature
dependencies: []
priority: medium
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents write non-atomic commits despite WBI guidance. The 'and <verb>' pattern in a commit subject reliably signals two concerns bundled into one commit. Adding a post-commit lint step that detects this pattern gives immediate feedback while the agent is still in context to split or fixup.

The same imperative verb list needed for descriptive comment detection (llm-tools-anp) applies here — verbs like Fix, Add, Update, Remove, etc. indicate the action in a commit subject. A shared verbs file (e.g. tools/agent-lint-verbs.txt) should serve both the commit linter and the comment detector to avoid duplication.

Also relevant: the commit footer contains 'Authored By: <agent> (<model>)'. A session ID could be appended here to link commits back to the session that produced them, complementing the existing OPENCODE_SESSION_ID injection. This creates a traceable audit trail from commit → session → PR.

Build tools/check-commit-message (shell or Python) that:
1. Reads the commit message from stdin or $1
2. Extracts the subject line
3. Flags if subject matches 'and <verb>' pattern using shared verb list
4. Output: 'non-atomic commit: subject contains "and <verb>" — split into two commits'
5. Exit 1 on violation

Wire into the git() wrapper in tools/setup-shared-aliases.sh after a successful commit, or as a commit-msg git hook installed by the shell setup.
<!-- SECTION:DESCRIPTION:END -->
