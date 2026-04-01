---
name: mojo-rebase
description: Interactive rebase, fixup, and commit message rewriting patterns
triggers:
  - event: tool.execute.before
    tool: bash
    command: "git rebase"
---

# mojo-rebase

`git rebase -i <ref>` is safe to use. GIT_SEQUENCE_EDITOR halts with a break, prints the todo path.

**Moving changes to an earlier commit:**

```bash
# Mark the target commit as `edit` in the rebase todo
git rebase -i <ref>

# At the edit stop, stage the changes you want in this commit
git add -u .
git rebase --continue
# The later commit that originally had these lines becomes a no-op and is dropped
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
git commit --allow-empty -m "amend! feat(foo): add bar" -m "feat(foo): add bar

New body explaining why without outdated details.

Authored-By: claude-code (claude-3.7-sonnet)"

git rebase --autosquash origin/${DEFAULT_BRANCH}
```
