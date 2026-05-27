---
id: TASK-15
title: Extract stacked PR workflow lessons into dedicated documentation
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: low
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The recent epic (15 PRs) surfaced valuable lessons:

WORKFLOW DISCOVERIES:
- spr requires branch tracking origin/main (not feature branch)
- Branch names must use dashes, not slashes (spr fails otherwise)
- git-absorb automates fixup creation (stage changes, run absorb, autosquash)
- Each commit becomes independent PR for parallel review
- NEVER merge via GitHub UI (breaks stack)
- NEVER use git push directly (use spr update)

TOOLING IMPROVEMENTS NEEDED:
- forge needed --paginate flag (was limited to 30 items)
- pr-poll doesn't scale for stacked PRs (only sees PRs in session messages)
- Cross-platform sandbox mounting via arrays (not BWRAP_ARGS directly)
- Package version override system (overlays/default.nix)

AGENT PATTERNS:
- Interactive rebase techniques (GIT_SEQUENCE_EDITOR, GIT_EDITOR=true)
- amend! for non-interactive commit message rewording
- git rebase --autosquash (non-interactive, NEVER -i)

This knowledge should be:
1. Consolidated into workflow guide
2. Extracted into reusable skills/prompts
3. Used to improve agent tooling defaults
<!-- SECTION:DESCRIPTION:END -->
