---
id: TASK-66
title: Automatic context renewal through Herdr
status: Done
assignee: []
created_date: '2026-10-16 02:43'
updated_date: '2026-10-25 02:01'
labels:
  - workflow
dependencies:
  - TASK-64
  - TASK-65
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: medium
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When context renewal is needed, request a reasoned handoff, confirm readiness, let the turn settle, submit /compact to the current pane through Herdr, confirm that compaction actually occurred (not merely that input was delivered), then submit the resume entry. Any failure preserves work and pauses for the user; no blind or emergency fallback, background session, or same-pane clear. Continuation and renewal share one decision so separate controllers never issue competing commands. Includes source inspection of the candidate integrations (context meter, compact handoff, safe compact, auto-compactor) and sandbox access to the Herdr socket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Successful compaction is distinguished from terminal input acknowledgment
- [x] #2 Handoff or compaction failure pauses for the user
- [x] #3 Current-pane handoff, compact, and resume restores the interrupted permitted action
- [x] #4 Stop continuation and renewal never issue competing commands
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-65 review: Herdr's submitted /mojo-resume and the SessionStart compact hook's prompt must not both invoke mojo-resume in one renewal. The second one would see the consumed (stale) handoff and pause. Before renewal, `work-record handoff` must print current.

Final design:
- One decision per Stop, made in stop-continue. A current handoff in a Herdr pane writes the renewal request {handoff, session_id, pane, state: requested} beside the work record and allows the stop. At CLAUDE_RENEWAL_TOKENS (default 175000) of main-conversation context, it asks to finish the current step and run mojo-handoff, naming running workers without waiting for them. A stop after that request without a current handoff pauses for the user. An unreadable transcript adds a systemMessage. Outside Herdr, a current handoff tells the user to renew by hand.
- No Herdr socket in the sandbox. herdr-renew runs outside it, started by agents/claude-code/setup-shell.sh for $HERDR_PANE_ID, from cwd /. It watches the PID of the sandbox script: sandboxed-claude execs $AGENT_SANDBOX_SCRIPT, never a PATH lookup. The helper exits when that process does. The helper's package pins PATH to the Nix store. herdr runs only by an absolute path, /run/current-system/sw/bin/herdr or HERDR_RENEW_HERDR from the launching shell, and only once `--resolve-herdr` has walked its whole chain: /, each directory and symlink, and the file are root-owned, and no directory is writable by others unless sticky. Otherwise renewal is off for the session, with a message saying why.
- The helper validates each request: its own pane, and a hex handoff equal to the current linked handoff. It ignores requests left before it started, attempts each handoff at most once, waits for an idle pane, and submits only /compact and /mojo-resume. Compaction counts only when compact-resume marks the attempt that was armed before /compact. Accepted risk: the sandbox can forge that mark, and the worst case is /mojo-resume in an idle session that was not compacted. Any failure pauses with the handoff intact. Every read of sandbox-writable files is bounded by a timeout. The log is ~/.local/state/claude-code/renewal.log, outside the sandbox, and is trimmed.
- setup-shell.sh exports HERDR_AGENT=claude in a Herdr pane, so Herdr recognizes the sandboxed Claude.

AC3 verified live 2026-10-24: a handoff in a Herdr pane, then the Stop hook request. renewal.log logged "renewing handoff 27f2015…" at 21:59:17 and "resumed handoff 27f2015…" at 21:59:56. The resumed context reached mojo-resume with the handoff current.
<!-- SECTION:NOTES:END -->
