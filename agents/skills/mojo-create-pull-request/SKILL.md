---
name: mojo-create-pull-request
description: Publish committed work in a new pull request
---

# mojo-create-pull-request

Run the relevant quality gates and update the task tracker before publication. Then publish the branch and create the pull request without asking for another confirmation.

```bash
git pull --rebase
git push -u origin HEAD
forge pr create --title "..." --body "..."
```

Draft state and the `needs-human-review` label are applied automatically when LLM-authored commits still require human review.
