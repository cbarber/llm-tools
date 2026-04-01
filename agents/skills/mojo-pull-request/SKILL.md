---
name: mojo-pull-request
description: PR creation, status, and review feedback workflow
triggers:
  - event: tool.execute.after
    tool: bash
    command: "forge pr create"
---

# mojo-pull-request

```bash {exec}
echo "PR status from: `forge pr status`"
forge pr status
```

**Viewing PR status:**

```bash
forge pr view 123
forge pr comments 123
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
forge pr review-reply <pr-number> <comment-id> "Fixed in commit abc123"
```
