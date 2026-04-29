---
name: mojo-commit
description: Atomic commit workflow with conventional commit format
triggers:
  - event: tool.execute.after
    tool: "^(edit|write)$"
  - event: tool.execute.after
    tool: bash
    command: "git add"
---

# mojo-commit

```bash {exec}
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

if [[ -n "$default_branch" && "$current_branch" == "$default_branch" ]]; then
  echo "⚠ You are on the default branch ($default_branch). Create a feature branch before committing."
fi

git log --oneline "$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo origin/${DEFAULT_BRANCH})"...
```

Commit after edit. An atomic commit is self-contained, related, and fully-functional. Atomic does not mean granular — it means self-contained and intentional. Three commits that together implement one thing are not three atomic commits; they are one commit that leaked its drafts.

**Self-contained and related:** include all changes required for the commit's purpose, and only those changes. Do not mix unrelated concerns.

**Fully-functional:** every commit must leave the codebase buildable and working. Any checkout in history must be a valid stopping point.

**Atomicity check:** if your subject contains "and <verb>" (e.g. "fix X and update Y"), split it into two commits.

**Before pushing:** review commits since branching with `git log --oneline origin/main..HEAD`. Squash any fix-of-fix chains into the commit they belong to using `--fixup` and `--autosquash`.

Format: `<type>(<scope>): <subject>`

**Types:**

* `feat` - New feature for the user
* `fix` - Bug fix for the user
* `refactor` - Code restructuring without behavior change
* `test` - Adding or updating tests
* `docs` - Documentation changes
* `style` - Formatting, whitespace (no code change)
* `chore` - Build tasks, dependencies (no production code change)

**Body:** 1-2 sentences on WHY (motivation, rationale). Omit if subject is sufficient. Never itemize implementation.

**Footer:** `Authored-By: <agent> (<model>)`

**Example:**

```text
fix(sandbox): support XDG git config in Linux sandbox

Git reads both ~/.config/git/config (XDG) and ~/.gitconfig (legacy).
Linux sandbox only mounted legacy file, breaking XDG-only users.

Authored-By: claude-code (claude-3.7-sonnet)
```

When all commits are clean and work is complete: push and create a PR — do not ask for confirmation.

```bash
git push -u origin <branch>
forge pr create --title "..." --body "..."
```

* PR body must explain WHY the change was made
* Link to beads issue if applicable
* Draft state and `needs-human-review` label are set automatically when LLM-authored commits are present
