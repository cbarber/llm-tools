---
name: mojo-commit
description: Atomic commit workflow with conventional commit format
triggers:
  - event: tool.execute.after
    tool: "^(edit|write)$"
    worktree: true
  - event: tool.execute.after
    tool: bash
    command: "git add"
  - event: tool.execute.after
    tool: bash
    command: "git commit"
    action: reset
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

Write commit messages succinct and exact. Conventional Commits format. No fluff. Why over what.

**Subject line:**

- `<type>(<scope>): <imperative summary>` — `<scope>` optional
- Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci`, `style`, `revert`
- Imperative mood: "add", "fix", "remove" — not "added", "adds", "adding"
- ≤50 chars when possible, no hard cap

**Body (only if needed):**

- Skip entirely when subject is self-explanatory
- Add body only for: non-obvious *why*, breaking changes, migration notes, linked issues
- Wrap at 72 chars
- Never itemize implementation.
- Reference issues/PRs at end: `Closes #42`, `Refs #17`

**What NEVER goes in:**

- "This commit does X", "I", "we", "now", "currently" — the diff says what
- Emoji (unless project convention requires)
- Restating the file name when scope already says it

**Footer:** `Authored-By: <agent> (<model>)`

**Example:**

```text
fix(sandbox): support XDG git config in Linux sandbox

Linux sandbox script only mounted legacy file, breaking XDG-only users.

Authored-By: claude-code (claude-3.7-sonnet)
```

When all commits are clean and work is complete: push and create a PR — do not ask for confirmation.

```bash
git push -u origin <branch>
forge pr create --title "..." --body "..."
```

- Draft state and `needs-human-review` label are set automatically when LLM-authored commits are present
