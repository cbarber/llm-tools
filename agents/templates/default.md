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

Body is for nuanced information beyond a succinct summary, not an itemized list of changes. 

Footer should include an `Authored By: <agent> (<model>)


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
