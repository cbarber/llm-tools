# AGENTS.md

This file provides guidance to LLM agents (Claude Code, OpenCode, etc.) when working with code in this repository.

## Development Guidelines

* Be terse. Only provide examples if actually necessary for clarification
* Code must be self-documenting. Never add prescriptive comments that describe what code does. Only add descriptive comments that explain why (rationale, edge cases, non-obvious algorithms). When in doubt, name a variable or extract a function.
* Avoid function side effects. Functions are always better as a clear input and output.
* Strive for logical function organization. "clean code" and "one large function" are too dogmatic
* Avoid deep block nesting. Prefer conditions that return early.
* Do not update code through shell commands. When you're stuck, ask me to help with changes.
* Be strategic. Formulate a plan, consider all options, and ask questions before jumping to solutions.
* Remember neither you nor I are a god. Do not break your arm patting me on the back. Just continue working.
* Challenge my assumptions with compelling evidence.
* You are always on a branch. Delete code rather than versioning code.
* **When git commands fail, STOP and ask for help.** Do not attempt recovery with reset/stash/cherry-pick.

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

# View PR with comments
bash tools/forge pr view 123 --comments

# View review comments
bash tools/forge pr review-comments 1
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

5. Provide handoff for next session:
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

**Session start:** Run `temper init` - check state and pick work
**Every commit:** Run `temper commit` - review commit format
**Before PR:** Run `temper pr` - review PR workflow
**Session end:** Run `temper complete` - completion checklist
