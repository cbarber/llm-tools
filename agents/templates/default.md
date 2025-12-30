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

## Semantic Commit Messages

Format: <type>(<scope>): <subject>

<scope> is optional. Preferably for the issue.
Example

feat: add hat wobble
^--^  ^------------^
|     |
|     +-> Summary in present tense.
|
+-------> Type: chore, docs, feat, fix, refactor, style, or test.

More Examples:

    feat: (new feature for the user, not a new feature for build script)
    fix: (bug fix for the user, not a fix to a build script)
    docs: (changes to the documentation)
    style: (formatting, missing semi colons, etc; no production code change)
    refactor: (refactoring production code, eg. renaming a variable)
    test: (adding missing tests, refactoring tests; no production code change)
    chore: (updating grunt tasks etc; no production code change)

**Body rules:**
- 1-2 sentences on WHY, or omit if subject is sufficient
- Never itemize implementation details

Good: "Automates dependency updates every Sunday via GitHub Actions, creating PRs for review."
Bad: "- Schedule: Weekly\n- Manual trigger: workflow_dispatch\n- Auto-generates diff\n..."

Footer should include an `Authored By: <agent> (<model>)

## Agent PR Workflow

Agents create PRs via `bash tools/forge` - a unified wrapper for GitHub (gh) and Gitea (tea).

**IMPORTANT:** Always use `forge` for repository operations. Do not use `gh` or `tea` directly. Check `bash tools/forge --help` for available commands before attempting direct API calls.

**forge examples:**
```bash
bash tools/forge pr create --title "..." --body "..."
bash tools/forge pr view 123 --comments
bash tools/forge pr review-comments 1
```

**Basic workflow:**
1. Complete work on branch
2. Commit changes
3. Push: `git push -u origin <branch>`
4. Create PR: `bash tools/forge pr create --title "..." --body "..."`
5. Use `--draft` if tests fail or work incomplete

**PR body focus:**
- Why the change was made (motivation, rationale)
- Link to beads issue if applicable
- If draft: what's blocking completion

**Commit hygiene:**
- Use `git commit --fixup=<sha>` for review feedback
- Squash fixups with `git rebase --autosquash origin/main` (non-interactive)
- **NEVER use `git rebase -i`** - interactive rebases are forbidden
- Maintains atomic commits

See `tools/AGENT_API_AUTH.md` for detailed examples and full forge CLI reference.

## Landing the Plane (Session Completion)

**When ending a work session**, complete ALL steps. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push --force-with-lease
   git status  # MUST show "up to date with origin"
   ```
   If `git push --force-with-lease` fails, STOP and request manual intervention.

5. **Clean up** - Remove debug code, temp files.
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Create next session prompt in this exact format:
   ```
   Recent Work:
   - Completed issue-id: Summary of changes

   Repository State:
   - Branch: <branch-name> (<commit-hash>)
   - Beads: X closed, Y ready issues

   Context:
   - Important details for continuity
   ```
   This prompt should be ready to paste into the next AI session.

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If force-with-lease fails, abort and request help

## Quick Reference (by frequency)

**Every commit:**
- [Semantic Commit Messages](#semantic-commit-messages) - Succinct subject, body for nuance (not itemized lists)

**Every session end:**
- [Landing the Plane](#landing-the-plane) - Push before saying "done"

**As needed:**
- [Development Guidelines](#development-guidelines) - Code style, terseness
