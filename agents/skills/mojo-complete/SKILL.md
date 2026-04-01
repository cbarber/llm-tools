---
name: mojo-complete
description: Session completion checklist — fires when unpushed work remains
triggers:
  - event: session.idle
    when: "git log origin/HEAD..HEAD --oneline 2>/dev/null | grep -q ."
---

# mojo-complete

**Work is NOT done until pushed.** Complete ALL steps:

1. File issues for remaining work
2. Run quality gates (tests, linters, builds)
3. Update beads (close/update issues)
4. Push to remote:

   ```bash
   git pull --rebase
   bd sync
   git push --force-with-lease
   git status  # MUST show "up to date with origin"
   ```

5. Handoff for context:
   Provide brief context about what was accomplished for session continuity:

   ```text
   Recent Work:
   - Completed llm-tools-xxx: Brief summary of what changed and why

   PR Status:
   <EXECUTE: forge pr status and paste output here>

   Context:
   - Any non-obvious decisions or gotchas for next session
   ```

   Note: Repository state (branch, available issues) is auto-injected via temper — do not duplicate that information.
