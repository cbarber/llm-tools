---
name: mojo-edit-nudge
description: Minimal-editing instruction injected at the first edit of each commit cycle
once: true
triggers:
  - event: tool.execute.after
    tool: bash
    command: "git commit"
---

# mojo-edit-nudge

**Change only what is necessary.** Edit the minimum code required to accomplish the task. Do not rename variables, restructure functions, reformat blocks, or add comments unless that is the explicit goal.

**Preserve the original.** Treat existing code as deliberately written. If it works and is not the subject of the task, leave it exactly as it is.

**One concern per edit.** If you find yourself changing something "while you're in there," stop. That change belongs in a separate task.

**Comments explain why, not what.** Exception: a package or type may have one orientation sentence when the name alone doesn't convey its purpose. A comment states one fact and stops — rationale belongs in the ADR.

**Avoid side effects.** When unavoidable, encode them in the type system or make them obvious from the name or signature.

**Avoid deep nesting.** Return early.

**Delete code rather than commenting it out.**
