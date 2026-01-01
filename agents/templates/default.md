# AGENTS.md

This file provides guidance to LLM agents (Claude Code, OpenCode, etc.) when working with code in this repository.

## Development Guidelines

* Be succinct. Only provide examples if necessary
* Code must be self-documenting. Comments explain WHY, not WHAT
* Avoid function side effects. Clear input → output
* Avoid deep nesting. Return early
* Be strategic. Plan first, ask questions, then execute
* Challenge assumptions with evidence
* Delete code rather than commenting it out
* **When git commands fail, STOP and ask for help**

## Workflow

### init

**Check repository state and pick work:**

```bash
git status --short --branch

bash tools/forge pr status

if command -v bd >/dev/null 2>&1 && [[ -d .beads ]]; then
  echo ""
  echo "📋 Available work:"
  bd ready --limit=5
fi
```

**Next action based on branch state:**
- **On main, clean** → Pick issue, create feature branch
- **On feature branch, PR merged** → Return to main, create new branch
- **On feature branch, PR open** → Continue work or address review feedback
- **On feature branch, no PR** → Complete work and create PR

### commit

Format: `<type>(<scope>): <subject>`

**Types:**
- `feat` - New feature for the user
- `fix` - Bug fix for the user
- `refactor` - Code restructuring without behavior change
- `test` - Adding or updating tests
- `docs` - Documentation changes
- `style` - Formatting, whitespace (no code change)
- `chore` - Build tasks, dependencies (no production code change)

**Body:** 1-2 sentences on WHY (motivation, rationale). Omit if subject is sufficient. Never itemize implementation.

**Footer:** `Authored By: <agent> (<model>)`

**Example:**
```
fix(sandbox): support XDG git config in Linux sandbox

Git reads both ~/.config/git/config (XDG) and ~/.gitconfig (legacy).
Linux sandbox only mounted legacy file, breaking XDG-only users.

Authored By: claude-code (claude-3.7-sonnet)
```

### pull-request

**IMPORTANT:** Use `bash tools/forge` exclusively. Never call `gh` or `tea` directly.

Forge is a unified wrapper for GitHub (gh) and Gitea (tea). Check `bash tools/forge --help` before attempting direct API calls.

**Workflow:**
```bash
# Create PR
git push -u origin <branch>
bash tools/forge pr create --title "..." --body "..."

# View PR (includes all comments)
bash tools/forge pr view 123

# View all comments only
bash tools/forge pr comments 1

# Reply to specific review comment
bash tools/forge pr review-reply 1 123456789 "Fixed in commit abc123"
```

**PR body must explain:**
- WHY the change was made (motivation, rationale)
- Link to beads issue if applicable
- What's blocking completion (if using --draft)

**Addressing review feedback:**
```bash
git commit --fixup=<sha>              # Fix specific commit
git rebase --autosquash origin/main   # Squash fixups (non-interactive, NEVER use -i)
git push --force-with-lease
```

See `tools/AGENT_API_AUTH.md` for detailed examples and full forge CLI reference.

### complete

**Work is NOT done until pushed.** Complete ALL steps:

1. File issues for remaining work
2. Run quality gates (tests, linters, builds)
3. Update beads (close/update issues)
4. Push to remote:
   ```bash
   git pull --rebase
   bd sync
   git push --force-with-lease
   git status  # MUST show "up to date with origin"
   ```
   If `--force-with-lease` fails, STOP and ask for help.

5. Handoff for context:
   Provide brief context about what was accomplished for session continuity:
   ```
   Recent Work:
   - Completed llm-tools-xxx: Brief summary of what changed and why

   PR Status:
   <EXECUTE: bash tools/forge pr status and paste output here>

   Context:
   - Any non-obvious decisions or gotchas for next session
   ```

   Note: Repository state (branch, available issues) is auto-injected via temper - don't duplicate that information.

**Rules:**
- NEVER say "ready to push when you are" - YOU push
- NEVER stop before pushing
- Next session will auto-load state via temper

## Quick Reference

**Session start:** Run `temper init` - check state and pick work
**Every commit:** Run `temper commit` - review commit format
**Before PR:** Run `temper pr` - review PR workflow
**Session end:** Run `temper complete` - completion checklist
