---
name: mojo-update-pull-request
description: Publish additional commits to an existing pull request
---

# mojo-update-pull-request

Run the relevant quality gates, update the task tracker, and publish the current branch. Use force-with-lease only when the reviewed history was rewritten.

```bash
git pull --rebase
git push --force-with-lease
git status
forge pr status
```

Update the pull request title or body only when the scope materially changed.
