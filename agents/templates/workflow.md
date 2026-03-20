# AGENTS.md

This file provides guidance to LLM agents when working with code in this repository.

## Agent Environment

You are running in a sandboxed environment by default. The sandbox isolates filesystem access while allowing read-write to the current project directory and necessary git directories. Check `IN_AGENT_SANDBOX` environment variable to confirm sandbox status.

## Guidelines

* Be succinct. Only provide examples if necessary
* Be strategic. Plan first, ask questions, then execute
* Challenge assumptions with evidence

## Workflow

### init

**Check repository state and pick work:**

```bash
# Show agent environment context
if [[ -n "${OPENCODE:-}" ]]; then
  echo "Agent: OpenCode"
elif [[ -n "${CLAUDE_CODE:-}" ]]; then
  echo "Agent: Claude Code"
else
  echo "Agent: Unknown"
fi

if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  echo "Sandbox: enabled"
else
  echo "Sandbox: disabled"
fi

echo ""

git status --short --branch

bash tools/forge pr status

if command -v bd >/dev/null 2>&1 && [[ -d .beads ]]; then
  echo ""
  echo "📋 Available work:"
  bd ready --limit=5
fi
```

**Next action based on branch state:**
- **On $DEFAULT_BRANCH, clean** → Pick issue, create feature branch
- **On feature branch, PR merged** → Return to $DEFAULT_BRANCH, create new branch
- **On feature branch, PR open** → Continue work or address review feedback
- **On feature branch, no PR** → Complete work and create PR

### dev-guidelines (tool.execute.before:edit|write)

* Code must be self-documenting. Comments explain WHY, not WHAT
* Avoid function side effects. Clear input → output
* Avoid deep nesting. Return early
* Delete code rather than commenting it out

### commit (tool.execute.after:edit|write)

```
git log --oneline "$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo origin/${DEFAULT_BRANCH})"...
```

Commit after edit. An atomic commit is self-contained, related, and fully-functional.

**Self-contained and related:** include all changes required for the commit's purpose, and only those changes. Do not mix unrelated concerns. For example, adding a new input field to a form and fixing a cache timeout bug are two commits, not one — even if both touch the same file.

**Fully-functional:** every commit must leave the codebase buildable and working. Any checkout in history must be a valid stopping point.

**Atomicity check:** if your subject contains "and <verb>" (e.g. "fix X and update Y"), split it into two commits.

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

**Rewriting commit messages:**

To change a commit message further back in history, use `amend!` commits:

```bash
# Get the subject line of the commit to reword
git log --format="%s" -1 <commit-hash>

# Create amend commit (subject = "amend! <original-subject>", body = new full message)
git commit --allow-empty -m "amend! <original-subject>" -m "<new-full-message-including-subject>"

# Apply via autosquash
git rebase --autosquash origin/${DEFAULT_BRANCH}
```

Example:
```bash
# Reword commit abc123 "feat(foo): add bar"
git commit --allow-empty -m "amend! feat(foo): add bar" -m "feat(foo): add bar

New body explaining why without outdated details.

Authored By: claude-code (claude-3.7-sonnet)"

git rebase --autosquash origin/${DEFAULT_BRANCH}
```

### pull-request (tool.execute.after:bash:.*forge pr create.*)

```bash
bash tools/forge pr status
```

**Creating PRs:**
```bash
git push -u origin <branch>
bash tools/forge pr create --title "..." --body "..."
```

**Viewing PR status:**
```bash
bash tools/forge pr view 123
bash tools/forge pr comments 123
```

**Addressing review feedback:**
```bash
# Option 1: Automatic fixup with git-absorb
git add <changed-files>
git absorb                                        # Automatically creates fixups for staged changes
git rebase --autosquash origin/${DEFAULT_BRANCH}  # Squash fixups

# Option 2: Manual fixup
git commit --fixup=<sha>                          # Fix specific commit
git rebase --autosquash origin/${DEFAULT_BRANCH}  # Squash fixups

# Option 3: Interactive rebase (reorder, drop, reword, squash)
git rebase -i <ref>
# GIT_SEQUENCE_EDITOR halts with a break, prints the todo path
# Edit the todo file, then: git rebase --continue
# If --continue opens an editor (reword/squash message):
# GIT_EDITOR prints the file path and exits — write message with -m or --amend -m

git push --force-with-lease
```

**Replying to review comments:**
```bash
bash tools/forge pr review-reply <pr-number> <comment-id> "Fixed in commit abc123"
```

**Key points:**
- NEVER call `gh` or `tea` directly — use `bash tools/forge`
- PR body must explain WHY the change was made
- Link to beads issue if applicable
- Use `--draft` when work is incomplete or tests are failing

See `tools/AGENT_API_AUTH.md` for token setup and full forge CLI reference.

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
