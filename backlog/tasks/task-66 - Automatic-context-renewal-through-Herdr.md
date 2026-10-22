---
id: TASK-66
title: Automatic context renewal through Herdr
status: In Progress
assignee: []
created_date: '2026-10-16 02:43'
updated_date: '2026-10-22 03:41'
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
- [ ] #3 Current-pane handoff, compact, and resume restores the interrupted permitted action
- [x] #4 Stop continuation and renewal never issue competing commands
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-65 review: Herdr's submitted /mojo-resume and the SessionStart compact hook's prompt must not both invoke mojo-resume in one renewal — the second render sees the consumed (stale) handoff and pauses. Readiness check before renewal: `work-record handoff` prints current.

Implemented: stop-continue makes the single continuation/renewal decision per Stop (main-chain context >= CLAUDE_RENEWAL_SOFT_TOKENS, default 150000, asks once per hook-driven run to finish the current step, record progress, and run mojo-handoff, after which ordinary continuation applies within the nudge bound; >= CLAUDE_RENEWAL_HARD_TOKENS, default 200000, asks only for mojo-handoff, and a hard request that yields no current handoff pauses; a current handoff in a Herdr pane launches herdr-renew and allows the stop). herdr-renew waits for an idle pane, re-checks the handoff, submits /compact, counts compaction only when the SessionStart compact hook (compact-resume) marks the renewal state compacted, then submits /mojo-resume once; any failure pauses with the handoff intact, one attempt per handoff. Neither request waits for running background workers: they keep running through compaction (code.claude.com/docs/en/context-window.md, sub-agents.md); the handoff lists them and resume waits for their reports. Sandbox mounts only the HERDR_SOCKET_PATH socket. AC3 open: needs the user's live current-pane handoff -> compact -> resume run in Herdr.

## Correction round 1 implementer (supersedes the Implemented paragraph above)
- One threshold: CLAUDE_RENEWAL_TOKENS (default 175000) of main-conversation context asks to finish the current step and run mojo-handoff, naming running workers, without waiting for them; a stop after that request without a current handoff pauses for the user. An unreadable or missing transcript adds a systemMessage instead of silently disabling renewal. Outside Herdr a current handoff tells the user to renew by hand.
- No Herdr socket in the sandbox (ef02dab reverted). herdr-renew runs outside the sandbox, started by agents/claude-code/setup-shell.sh for $HERDR_PANE_ID and exiting with the Claude process. Inside, stop-continue only writes the renewal request {handoff, session_id, pane, state: requested} beside the work record, and compact-resume marks it compacted only for the requesting session_id. The helper validates the request (own pane, hex handoff equal to the current linked handoff), ignores requests left before it started, acts at most once per handoff, and submits only /compact and /mojo-resume. Its log lives outside the sandbox (~/.local/state/claude-code/renewal.log), trimmed.
- Herdr recognition: agents/claude-code/setup-shell.sh exports HERDR_AGENT=claude in a Herdr pane, as agents/opencode/setup-shell.sh does HERDR_AGENT=opencode; Herdr reads process environments and so recognizes the sandboxed Claude. Its Claude integration only reports session identity. Unverified live.
- AC3 still open: needs the user's live run in Herdr.

## Correction round 2 implementer
- herdr-renew executes only from the Nix store: the package sets its PATH outright (coreutils, jq, work-record), and setup-shell.sh starts it by store path (HERDR_RENEW_PATH) with a herdr that `herdr-renew --resolve-herdr` resolves (readlink -f) into /nix/store, else prints why and does not start it. The package's install check runs test-herdr-renew-path.bats against the wrapper with planted binaries first on PATH.
- Every read of sandbox-writable files is bounded by timeout; all handoffs attempted are remembered; a compaction counts only when compact-resume confirms the attempt the helper armed the request with before /compact (accepted risk: the sandbox can read and forge it; worst case /mojo-resume in an uncompacted idle session); compaction wait 1800s, and its pause says to submit /mojo-resume once compaction finishes; a written renewal request tells the user how to renew by hand if nothing happens.
<!-- SECTION:NOTES:END -->
