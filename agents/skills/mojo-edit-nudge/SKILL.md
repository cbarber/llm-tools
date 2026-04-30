---
name: mojo-edit-nudge
description: Minimal-editing instruction injected at the first edit of each commit cycle
once: true
triggers:
  - event: tool.execute.before
    tool: "^(edit|write)$"
    action: fail
  - event: tool.execute.after
    tool: bash
    command: "git commit"
    action: reset
---

# mojo-edit-nudge

Your edit was not applied. Internalize these constraints, then retry:

**Change only what is necessary.** Edit the minimum code required to accomplish the task. Do not rename variables, restructure functions, reformat blocks, or add comments unless that is the explicit goal.

**Preserve the original.** Treat existing code as deliberately written. If it works and is not the subject of the task, leave it exactly as it is.

**One concern per edit.** If you find yourself changing something "while you're in there," stop. That change belongs in a separate task.
