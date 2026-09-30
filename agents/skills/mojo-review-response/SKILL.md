---
name: mojo-review-response
description: Address pull request review feedback and republish changes
---

# mojo-review-response

Resolve each review finding with a focused change, run the affected quality gates, and preserve atomic history with fixups when appropriate.

```bash
git add <changed-files>
git absorb
git rebase --autosquash origin/${DEFAULT_BRANCH}
git push --force-with-lease
```

Reply to resolved review threads with the commit that addressed them:

```bash
forge pr review-reply <pr-number> <comment-id> "Fixed in commit abc123"
```
