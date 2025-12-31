# AGENTS.md

This file provides guidance to LLM agents (Claude Code, OpenCode, etc.) when working with code in this repository.

## Starting a Session

**First action:** Check repository state and pick work.

```bash
git status              # What branch? Clean or dirty?
git log --oneline -3    # Recent commits
bd ready                # Available work
```

**Branch state determines next action:**
- **On main, clean** → Create feature branch for new work
- **On feature branch, PR merged** → Return to main, create new branch
- **On feature branch, PR open** → Continue existing work or address review feedback
- **On feature branch, no PR** → Complete work and create PR

## Development Guidelines

* Be terse. Only provide examples if necessary
* Code must be self-documenting. Comments explain WHY, not WHAT
* Avoid function side effects. Clear input → output
* Avoid deep nesting. Return early
* Be strategic. Plan first, ask questions, then execute
* Challenge assumptions with evidence
* Delete code rather than commenting it out
* **When git commands fail, STOP and ask for help**

## Semantic Commit Messages

Format: `<type>(<scope>): <subject>`

Types: feat, fix, refactor, test, docs, style, chore

**Body:** 1-2 sentences on WHY, or omit if subject is sufficient. Never itemize implementation.

**Footer:** `Authored By: <agent> (<model>)`

Examples:
```
fix(sandbox): support XDG git config in Linux sandbox

Git reads both ~/.config/git/config (XDG) and ~/.gitconfig (legacy).
Linux sandbox only mounted legacy file, breaking XDG-only users.

Authored By: claude-code (claude-3.7-sonnet)
```

## PR Workflow

Use `bash tools/forge` (not `gh`/`tea` directly). Check `bash tools/forge --help` first.

```bash
# Create PR
git push -u origin <branch>
bash tools/forge pr create --title "..." --body "..."

# Address review feedback
git commit --fixup=<sha>              # Fix specific commit
git rebase --autosquash origin/main   # Squash fixups (non-interactive only)
git push --force-with-lease

# NEVER use `git rebase -i` (interactive rebases forbidden)
```

**PR body:** Why the change (motivation), link to beads issue, what blocks completion (if draft)

## Session Completion

**Work is NOT done until pushed.** Complete ALL steps:

1. **File issues** for remaining work
2. **Run quality gates** (tests, linters, builds)
3. **Update beads** - Close/update issues
4. **Push** (MANDATORY):
   ```bash
   git pull --rebase
   bd sync
   git push --force-with-lease
   git status  # MUST be "up to date with origin"
   ```
   If `--force-with-lease` fails, STOP and ask for help.

5. **Hand off** - Provide next session prompt:
   ```
   Recent Work:
   - Completed issue-id: Summary
   - Created PR #N (status: open/merged)

   Repository State:
   - Branch: <branch> (<commit-hash>)
   - PR Status: <open/merged/none>
   - Main: <commit-hash>

   Next Action:
   - Work on issue-id (specific task)
   OR
   - Pick from: bd ready (3 issues available)

   Context:
   - Critical details only
   ```

**Rules:**
- NEVER say "ready to push when you are" - YOU push
- NEVER stop before pushing
- ALWAYS specify next action in handoff

## Quick Reference

**Session start:** Check state → pick work → create/continue branch
**Every commit:** Semantic format, WHY in body
**Session end:** Push everything, specify next action in handoff
