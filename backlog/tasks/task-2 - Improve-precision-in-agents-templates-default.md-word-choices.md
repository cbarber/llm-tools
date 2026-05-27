---
id: TASK-2
title: Improve precision in agents/templates/default.md word choices
status: To Do
assignee: []
created_date: '2026-05-27 02:39'
updated_date: '2026-05-27 02:40'
labels:
  - task
dependencies: []
priority: medium
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context

Audit identified 13 imprecise word choices in agents/templates/default.md that reduce clarity:
- Ambiguous terms ('terse', 'strategic', 'quality gates')
- Vague directives ('if necessary', 'side effects', 'check state')
- Negative framing (what NOT to do vs what TO do)
- Passive voice obscuring agency
- Jargon lacking operational definitions

## Decision Criteria

When revising word choices:
1. **Precision over brevity** - Choose terms with single clear interpretation
2. **Positive directives** - Specify desired behavior, not prohibited behavior
3. **Concrete over abstract** - Prefer actionable terms ('run git status' vs 'check state')
4. **Active voice** - Make agent responsibility explicit
5. **No jargon** - Replace domain terms with plain language when possible
6. **Maintain terseness** - Edits should maintain or reduce line length

## Reconciliation Required

**CRITICAL**: Changes to default.md must be reconciled with AGENTS.md:
- AGENTS.md is the canonical source used by this repository
- default.md is the template for user repositories
- Both files share overlapping guidelines (commit format, PR workflow, session completion)
- Word choice improvements should apply consistently to both files

**Process:**
1. Read current AGENTS.md to identify matching sections
2. Apply precision improvements to default.md
3. Backport applicable changes to AGENTS.md
4. Verify both files use consistent terminology
5. Test that improved language doesn't conflict with existing workflows

**Example conflicts to check:**
- 'terse' appears in both files - ensure consistent replacement
- Commit message guidance duplicated - update both
- Session completion checklist - verify step wording matches

Note: Audit was performed on specific line numbers that may shift if template evolves before this work begins.
<!-- SECTION:DESCRIPTION:END -->
